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

local lookup = {'Unknown-Unknown','Warrior-Fury','Druid-Balance','Druid-Restoration','Mage-Frost','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Evoker-Devastation','Evoker-Augmentation','Warlock-Destruction','DeathKnight-Unholy','Warrior-Protection','Shaman-Restoration','Monk-Brewmaster','Hunter-BeastMastery','DeathKnight-Frost','Warlock-Demonology','Hunter-Survival','Priest-Holy','Warlock-Affliction','Rogue-Subtlety','Priest-Discipline','Shaman-Elemental','Shaman-Enhancement','Monk-Mistweaver','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Marksmanship','DeathKnight-Blood','Druid-Feral','Druid-Guardian','Priest-Shadow','Mage-Arcane','Rogue-Assassination','Warrior-Arms','Evoker-Preservation','Monk-Windwalker',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aaffoxx:BAAALgAECgEJAQAAAA==.Aagonyy:BAAALgAECgEJAwAAAA==.',
Ae='Aenninicus:BAAALgAECgEJAgAAAA==.Aernoth:BAAALgAECgUJDQAAAA==.',
Af='Affox:BAAALgAECgEJAQAAAA==.',
Ak='Akaidia:BAAALgAECgYJBgABLgAECgYJCwABAAAAAA==.',
Al='Alderan:BAABLgAECn8lAAICAAcJIg4dQwA5AQACAAcJIg4dQwA5AQAAAA==.Aleinas:BAABLgAECn8kAAMDAAcJKxbLMwBKAQADAAcJKxbLMwBKAQAEAAQJQQixlQCIAAAAAA==.Alektophobia:BAAALgAFFAEJAQAAAA==.Alendra:BAAALgAECgEJAQABLgAECgYJFAAFANQfAA==.Alluisice:BAAALgAECgYJBgAAAA==.Allysaun:BAAALgAECgUJBgAAAA==.Alpharoach:BAAALgADCgYJBgAAAA==.Alufina:BAAALgAECgYJBgABLgAECgkJHAAGAAwVAA==.Alzeinrich:BAABLgAECn8XAAMHAAcJSQd93gDgAAAHAAcJmgV93gDgAAAIAAQJbwjJNwCAAAAAAA==.',
Am='Amorina:BAABLgAECn8cAAIHAAgJzxWpVQDKAQAHAAgJzxWpVQDKAQAAAA==.',
An='Anda:BAAALgAECgMJAwAAAA==.Andarnn:BAAALgAECgEJAQAAAA==.Andracca:BAABLgAECn8eAAMJAAkJFAspDABOAQAJAAkJFAspDABOAQAKAAEJQAXynAAkAAAAAA==.Andromeda:BAABLgAECn8XAAIEAAkJXQzzTwBPAQAEAAkJXQzzTwBPAQAAAA==.Aner:BAAALgAECgEJBgAAAA==.Angrygnome:BAACLgAFFH8JAAILAAMJex44CAAUAQALAAMJex44CAAUAQAuAAQKfx4AAgsACQmqILoBAL4CAAsACQmqILoBAL4CAAAA.Angélique:BAAALgAFFAIJAwABLgAFFAYJGQAMAOUhAA==.Antcension:BAAALgADCgUJBQAAAA==.Antemental:BAAALgAECgYJEAAAAA==.Anthigos:BAAALgAECgMJAwAAAA==.',
Ar='Arax:BAABLgAECn8dAAINAAcJ7yHTDgD9AQANAAcJ7yHTDgD9AQAAAA==.Arcada:BAAALgAECgUJBQABLgAECgUJBQABAAAAAA==.Arcaidious:BAAALgAECgUJCgABLgAECggJJAAOAFcRAA==.Arcamoon:BAAALgAECgIJAgABLgAECgUJBQABAAAAAA==.Arcashi:BAAALgADCgcJCgABLgAECgUJBQABAAAAAA==.Arcxdd:BAAALgAECgQJBAAAAA==.Areuawizard:BAAALgAECgYJBgAAAA==.Arianlion:BAAALgAECgEJAgAAAA==.Ariantheone:BAAALgAECgEJAQAAAA==.Armistice:BAAALgAECgEJAgAAAA==.Arowenn:BAAALgADCgMJAwAAAA==.Arrokoth:BAAALgAECgQJBwAAAA==.Artana:BAAALgAECgIJAgAAAA==.Artistic:BAAALgADCgYJBgAAAA==.',
As='Askook:BAAALgAECgkJEwAAAA==.Astolvik:BAAALgAECgQJBgAAAA==.',
At='Attachedplag:BAAALgAECgYJEwAAAA==.Atulwa:BAABLgAECn8pAAIOAAkJ6xfbIwA3AgAOAAkJ6xfbIwA3AgAAAA==.',
Au='Aurinox:BAABLgAECn8dAAIFAAYJ9w4HugATAQAFAAYJ9w4HugATAQAAAA==.Autodrive:BAABLgAECn8VAAIPAAgJaRvqAADPAQAPAAgJaRvqAADPAQAAAA==.',
Av='Avralea:BAABLgAECn9JAAIPAAgJ8BvOEgAdAgAPAAgJ8BvOEgAdAgAAAA==.',
Az='Azenthal:BAAALgAECgEJAQAAAA==.Azurestrider:BAAALgAECgEJAQAAAA==.',
['Aç']='Açhilles:BAAALgAECgYJCAABLgAECgkJHQAEAMYYAA==.',
Ba='Bananahammik:BAAALgAECgYJDgAAAA==.Banzen:BAABLgAECn8eAAIQAAUJ/g/GEgClAAAQAAUJ/g/GEgClAAAAAA==.Basz:BAACLgAFFH8MAAIMAAQJKQ/4JADQAAAMAAQJKQ/4JADQAAAuAAQKf0MAAwwACAn4HeYEAG0BAAwACAn4HeYEAG0BABEABgmhE+ACALgAAAAA.',
Be='Beefburglar:BAAALgAECgYJBgAAAA==.Beginagain:BAAALgADCgcJCQAAAA==.Belfias:BAAALgAECgEJAgABLgAECgkJFgARAFMaAA==.Belgran:BAABLgAECn8WAAIRAAkJUxrSAwA9AgARAAkJUxrSAwA9AgAAAA==.Belmonte:BAAALgADCgEJAQAAAA==.Belris:BAAALgAECgMJAwAAAA==.Berunma:BAABLgAECn8YAAIQAAgJ2BBveABPAQAQAAgJ2BBveABPAQAAAA==.Betabill:BAAALgAECgUJBQAAAA==.',
Bh='Bhain:BAABLgAECn8hAAMSAAcJ5R3lSgDpAQASAAcJ5R3lSgDpAQALAAEJaA2FdAAwAAABLgAFFAUJFgAHAKwfAA==.',
Bi='Bileshots:BAABLgAECn8UAAITAAgJNRciHAC8AQATAAgJNRciHAC8AQAAAA==.Biowolf:BAACLgAFFH8jAAIFAAUJNQi1IADTAAAFAAUJNQi1IADTAAAuAAQKfywAAgUACQneFBVEAA8CAAUACQneFBVEAA8CAAAA.Birdhunter:BAAALgAFFAEJAQAAAA==.Bishopixixix:BAAALgAECgYJCwABLgAECgcJDwABAAAAAA==.Bits:BAABLgAECn8rAAISAAkJWgfecwBSAQASAAkJWgfecwBSAQAAAA==.',
Bj='Bjoren:BAABLgAECn8wAAIUAAkJGyRSAwBcAwAUAAkJGyRSAwBcAwAAAA==.',
Bl='Blackdread:BAAALgADCgYJBgAAAA==.Blasterjenny:BAAALgAECgQJBQAAAA==.Bloodcaptain:BAABLgAECn8cAAMLAAkJORfuBgDtAQALAAkJZBbuBgDtAQAVAAYJshf6CAC3AQAAAA==.',
Bo='Bohma:BAAALgADCgEJAQAAAA==.Boopblast:BAAALgAECgQJCAAAAA==.Bootiebang:BAABLgAECn8WAAIWAAcJrQOoOgDjAAAWAAcJrQOoOgDjAAAAAA==.Bootieknight:BAAALgAECgUJCAAAAA==.Bootycaall:BAAALgADCgkJGwAAAA==.Bootycall:BAAALgADCgkJCQAAAA==.Boroth:BAAALgADCgcJBwAAAA==.',
Br='Breetech:BAAALgAECgIJAgAAAA==.Brett:BAAALgAECgEJAQAAAA==.Breé:BAAALgAECgEJAQAAAA==.Brianx:BAAALgADCgIJAgAAAA==.Brklyn:BAAALgAFFAEJAQAAAA==.Brockshot:BAAALgADCgcJBwAAAA==.Brokki:BAAALgADCgEJAQAAAA==.',
Bu='Buckaroo:BAAALgAECgQJBQAAAA==.Bucknastey:BAAALgAECgIJAgAAAA==.Bucknekkid:BAABLgAECn8UAAIHAAkJpwWyyAD9AAAHAAkJpwWyyAD9AAAAAA==.Buckwhild:BAABLgAECn8jAAMUAAgJxiEzCQDWAgAUAAgJ4CAzCQDWAgAXAAMJfB2GBAAKAQAAAA==.Burrhus:BAAALgAECgQJBAAAAA==.',
Ca='Cagomei:BAAALgADCggJDgAAAA==.Caladbolg:BAABLgAECn9LAAMIAAgJ2CJEAACoAgAIAAgJ2CJEAACoAgAHAAEJkAP5VwEnAAAAAA==.Camrillem:BAAALgAFFAEJAQAAAA==.Cannacola:BAABLgAECn8mAAMYAAYJvB/KKwCXAQAZAAYJ1BzoDQDeAQAYAAYJOh7KKwCXAQAAAA==.Carebearr:BAAALgAECgMJAwAAAA==.',
Ce='Cearius:BAAALgAECgYJCgABLgAFFAYJFQASAEweAA==.Celthis:BAAALgADCgcJBwABLgAECgUJCQABAAAAAA==.Cerdwin:BAAALgAECgEJAQABLgAECgYJFAAFANQfAA==.Cesàrè:BAABLgAECn8eAAIaAAgJpwm2CwCvAAAaAAgJpwm2CwCvAAAAAA==.',
Ch='Chahra:BAABLgAECn8bAAIbAAkJzg1aEABHAQAbAAkJzg1aEABHAQAAAA==.Chammie:BAAALgAECgYJBgAAAA==.Chamuki:BAACLgAFFH8GAAMcAAMJ4g8/IgCJAAAcAAIJZhY/IgCJAAAdAAEJ2wKkpwAyAAAuAAQKfyIABBwACAn4HO8OADcCABwABwnBIO8OADcCAB0ABQm2DcK5ALgAABsAAgkXFtcwAEAAAAEuAAUUBQkaAAMAsR8A.Chaosbolt:BAAALgAECgEJBQAAAA==.Cheesecake:BAACLgAFFH8ZAAMMAAYJ5SHrKADGAQAMAAYJ5SHrKADGAQARAAIJ3A9CHgCSAAAuAAQKfyYAAwwACQl+JcQCAK4DAAwACQl+JcQCAK4DABEAAwn6GuEmAJwAAAAA.Cheesecaké:BAAALgAFFAIJAgABLgAFFAYJGQAMAOUhAA==.Cheesuspiece:BAAALgADCgIJAgAAAA==.Chrispbacon:BAAALgAECgMJBAAAAA==.Chuubak:BAAALgAECgkJBwAAAA==.',
Cl='Clangeddin:BAAALgAECgQJBAAAAA==.Clangedin:BAABLgAECn8rAAICAAgJzQkCBwDFAAACAAgJzQkCBwDFAAAAAA==.',
Co='Cobalt:BAAALgADCgUJBQABLgAFFAMJCgASADYbAA==.Colonidus:BAAALgADCgUJBQAAAA==.Coondic:BAAALgADCgEJAQAAAA==.Coreydruid:BAAALgAECgMJBwAAAA==.Coreypala:BAAALgAECgIJBAAAAA==.Coreysham:BAAALgAECgQJBQAAAA==.Corily:BAAALgADCgcJHAAAAA==.Corsten:BAABLgAECn8sAAINAAgJYBF6AQBwAQANAAgJYBF6AQBwAQAAAA==.Cosmictonic:BAAALgADCgYJBgAAAA==.',
Cr='Crabpack:BAAALgADCgIJAgAAAA==.Crayoneater:BAAALgAECgQJBAAAAA==.Crippleswagg:BAAALgAECgYJAQAAAA==.Croisades:BAAALgAECgQJCgAAAA==.Crosis:BAAALgADCgcJFwAAAA==.Crowmatic:BAABLgAECn8aAAIMAAkJ+h5fJwBlAgAMAAkJ+h5fJwBlAgAAAA==.Crusadan:BAAALgADCgYJBgAAAA==.Cryo:BAAALgAECgEJAQAAAA==.',
Cu='Cucklizard:BAAALgAECgEJAQAAAA==.Cute:BAABLgAFFH8NAAICAAMJNCOSKAATAQACAAMJNCOSKAATAQAAAA==.',
['Cà']='Càhos:BAAALgADCgUJBQAAAA==.',
Da='Dakon:BAABLgAECn83AAMIAAkJThoNCgArAgAIAAkJThoNCgArAgAHAAIJcBi7DAF9AAAAAA==.Dalune:BAABLgAECn87AAIYAAgJOQxYAwA0AQAYAAgJOQxYAwA0AQAAAA==.Daneaus:BAABLgAECn8sAAIEAAkJviH0BQBZAwAEAAkJviH0BQBZAwAAAA==.Daniellson:BAACLgAFFH8HAAITAAMJ1g1YIQDOAAATAAMJ1g1YIQDOAAAuAAQKfxgABB4ACAkoEesvALUBAB4ACAkoEesvALUBABMAAQk+EKFhADgAABAAAQkAAFrcABcAAAEuAAUUBgkRAB8ApRgA.Daredevil:BAAALgAECgYJCQABLgAECggJFwAMALYcAA==.Dargonath:BAAALgAFFAEJAgAAAA==.Darkchronos:BAAALgAECgEJAgAAAA==.Darkehawke:BAAALgAECgEJAQAAAA==.Darkscorp:BAAALgADCgkJDgAAAA==.Darkwolf:BAACLgAFFH8IAAIMAAQJkQbxhwD6AAAMAAQJkQbxhwD6AAAuAAQKfzcAAwwACQlnFC83ACICAAwACQlnFC83ACICAB8ACAldBikyANQAAAAA.Darnuus:BAAALgAECgYJDQABLgAECggJKgAKAPILAA==.Datromandude:BAAALgAECgUJCAAAAA==.Dawnbringer:BAAALgADCgQJBAAAAA==.',
Db='Dblaster:BAAALgAECgUJCwAAAA==.',
De='Deathbydruid:BAABLgAECn8oAAMEAAkJyANFfwC8AAAEAAkJyANFfwC8AAADAAYJ1QCEfwBJAAAAAA==.Deathnelf:BAABLgAECn8bAAQRAAkJ5AnKFgAiAQARAAgJAgvKFgAiAQAMAAYJYQXU8gC9AAAfAAIJIQOICQBAAAAAAA==.Deazraelle:BAABLgAECn8cAAISAAgJnRvyPADoAQASAAgJnRvyPADoAQAAAA==.Decimator:BAAALgADCggJHwAAAA==.Declan:BAAALgADCgUJBQAAAA==.Dedric:BAABLgAECn8nAAQgAAgJ8wqDIwDuAAAgAAgJGwiDIwDuAAADAAgJKgRJTgDTAAAhAAEJNRcqbAA+AAAAAA==.Deesis:BAAALgADCgEJAQAAAA==.Dellin:BAABLgAECn8qAAIDAAkJFBcgGAAMAgADAAkJFBcgGAAMAgAAAA==.Demeco:BAEALgAFFAQJBAABLgAFFAkJJAAGAHAcAA==.Demonch:BAAALgAECgUJCAAAAA==.Demonweasel:BAAALgAFFAEJAQABLgAFFAIJBgASAPAWAA==.Depeche:BAABLgAECn8eAAIdAAcJihG+mgDrAAAdAAcJihG+mgDrAAAAAA==.Deralle:BAABLgAECn8qAAIKAAgJ8gvMOQBFAQAKAAgJ8gvMOQBFAQAAAA==.Dethrift:BAAALgAECgEJAQAAAA==.',
Di='Dil:BAAALgAECgIJAwABLgAECggJGAAFAJUaAA==.Diminuendo:BAAALgAECgcJEAAAAA==.',
Do='Donalda:BAAALgAECgEJAQAAAA==.Dorillion:BAAALgAECgUJCQAAAA==.Dorozh:BAABLgAECn8fAAILAAgJfRTvCQCnAQALAAgJfRTvCQCnAQAAAA==.',
Dr='Draconx:BAAALgADCgYJBgAAAA==.Draghr:BAAALgAECgQJBAAAAA==.Dragonzmage:BAAALgAECgMJAwAAAA==.Dragskar:BAAALgADCgUJBQAAAA==.Drala:BAABLgAECn8hAAMXAAkJZhPoFwAVAgAXAAkJZhPoFwAVAgAUAAEJ2w77ggAuAAAAAA==.Dreadmage:BAAALgADCgUJBQABLgADCgUJCQABAAAAAA==.Dreadpally:BAAALgADCgEJAQABLgADCgUJCQABAAAAAA==.Dreadsham:BAAALgADCgIJAgABLgADCgUJCQABAAAAAA==.Dreco:BAAALgADCgcJBwAAAA==.Driver:BAEBLgAFFH8FAAIHAAIJSR2RgQCyAAAHAAIJSR2RgQCyAAABLgAFFAUJEAASALYLAA==.Dryconias:BAACLgAFFH8MAAIHAAMJvBZdIwCRAAAHAAMJvBZdIwCRAAAuAAQKfzUAAwcACQkqHKYhAIACAAcACQkqHKYhAIACAAgAAQmfCNBUACcAAAAA.Drèadpriest:BAABLgAECn8VAAQXAAUJwR2JJQCjAQAXAAUJux2JJQCjAQAUAAUJ0hR9QgDhAAAiAAIJCRMGUQCJAAAAAA==.Drôgô:BAABLgAECn8VAAIQAAYJnhM7TgB+AQAQAAYJnhM7TgB+AQABLgAECggJCAABAAAAAA==.',
Du='Dunkelzhan:BAABLgAECn9dAAIFAAkJwB9QAQDaAgAFAAkJwB9QAQDaAgAAAA==.Duntack:BAAALgADCgEJBAAAAA==.',
Dy='Dyana:BAABLgAECn8fAAIQAAgJ2BVJRgDPAQAQAAgJ2BVJRgDPAQAAAA==.',
Dz='Dz:BAACLgAFFH8MAAMGAAQJhRkuIAAcAQAGAAQJhRkuIAAcAQAHAAQJPwmwVgACAQAuAAQKf0QAAwYACQlBJlsAAN8DAAYACQlBJlsAAN8DAAcABAktDqb4AMAAAAAA.',
['Dø']='Dømimømmÿ:BAAALgAECgUJCAAAAA==.',
Ea='Earts:BAAALgAECgYJBgAAAA==.',
Ec='Ecowolf:BAAALgADCgkJCQABLgADCgkJMgABAAAAAA==.',
Ed='Edgyname:BAABLgAECn8UAAIdAAcJBCASMwD5AQAdAAcJBCASMwD5AQAAAA==.Edgyvoid:BAAALgADCgYJDAAAAA==.Edlund:BAABLgAECn8jAAIJAAkJfQ1jCACqAQAJAAkJfQ1jCACqAQAAAA==.',
Ef='Effyinzpjake:BAAALgAECgYJDgAAAA==.',
Ei='Eianistic:BAAALgADCgEJAQAAAA==.',
El='Elbiee:BAAALgAECggJCAABLgAECgkJFAAYACIZAA==.Eleos:BAAALgAECgUJBwAAAA==.Elfvispresly:BAAALgAECgEJAQABLgAECgkJDwABAAAAAA==.Ellenee:BAAALgADCgMJAwAAAA==.Ellinor:BAAALgADCgkJMgAAAA==.Elvy:BAABLgAECn8vAAIDAAkJVxgbGgD7AQADAAkJVxgbGgD7AQAAAA==.',
En='Enngin:BAAALgAFFAMJBAAAAA==.Enragee:BAAALgAECgEJAgABLgAECgcJGQAOAIUiAA==.Enroks:BAAALgAECgUJBQAAAA==.',
Er='Erebus:BAAALgAECgYJDAAAAA==.Erythra:BAAALgAECgQJBAAAAA==.',
Ev='Evildefiant:BAAALgAECgEJAQAAAA==.Evilfoxx:BAAALgADCgQJBQAAAA==.',
Ex='Exsalsior:BAAALgADCgYJBgAAAA==.',
Ey='Eyedoc:BAAALgADCgQJBAAAAA==.',
Fa='Fabulousness:BAABLgAECn8vAAIUAAkJCiHoBAAxAwAUAAkJCiHoBAAxAwAAAA==.',
Fe='Fearliz:BAAALgADCgEJAQAAAA==.',
Fi='Fifefrost:BAAALgAECgQJBAAAAA==.Fishingsucks:BAAALgAECgcJCgAAAA==.Fiurich:BAAALgAFFAEJAQAAAA==.',
Fl='Flexi:BAAALgADCgEJAQAAAA==.Flitred:BAAALgAECggJDwAAAA==.Flock:BAAALgAECgcJDwAAAA==.',
Fo='Foxx:BAAALgAECgUJDQAAAA==.',
Fr='Framboise:BAABLgAECn8ZAAICAAYJUQcaYAAwAQACAAYJUQcaYAAwAQAAAA==.Frostybolt:BAAALgAECgUJBwAAAA==.',
Fu='Furryriver:BAAALgAECgcJEAAAAA==.Furytotem:BAAALgAECgcJEgABLgABCgIJAgABAAAAAA==.',
['Fø']='Føxx:BAAALgAECgEJAQAAAA==.',
Ga='Galadhras:BAAALgADCgYJFAAAAA==.Galdryn:BAAALgADCgIJAQAAAA==.Galianna:BAABLgAECn8WAAIUAAgJOhI1IQC5AQAUAAgJOhI1IQC5AQAAAA==.Gamboslice:BAACLgAFFH8FAAIRAAIJzgYtCQB7AAARAAIJzgYtCQB7AAAuAAQKfx4AAhEACAm2FuoKAMwBABEACAm2FuoKAMwBAAAA.Garkevon:BAAALgAECgQJAwAAAA==.',
Ge='Gemeni:BAAALgAECgEJAQAAAA==.Gevul:BAACLgAFFH8HAAISAAMJNA04JQCLAAASAAMJNA04JQCLAAAuAAQKf2kAAxIACQnyG6YZAIoCABIACQnfG6YZAIoCAAsABAnlEwMkAJIAAAAA.',
Gh='Ghostess:BAAALgADCgkJAQAAAA==.Ghrank:BAABLgAECn8jAAQSAAgJyA6oAwBqAQASAAgJyA6oAwBqAQAVAAYJHwgMHQDWAAALAAYJ8QcHIgCfAAAAAA==.',
Gi='Gilliruni:BAAALgADCgUJBQAAAA==.Gitpull:BAAALgAECggJDgAAAA==.',
Gl='Glazul:BAAALgAECgUJBwAAAA==.Glimley:BAAALgADCgMJAwAAAA==.',
Gn='Gnimsh:BAAALgAECgEJAwAAAA==.Gnorst:BAAALgADCgkJCgAAAA==.',
Go='Goodfoxx:BAAALgAECgEJAQAAAA==.Goreolio:BAAALgADCgkJDwABLgAECgYJEQABAAAAAA==.',
Gr='Grandmatank:BAAALgADCgkJCQAAAA==.Grasshopaa:BAAALgADCgYJCQAAAA==.Grassy:BAAALgADCgkJCQAAAA==.Greengoatlin:BAAALgADCgcJBwAAAA==.Gremlock:BAAALgAECgEJAQAAAA==.Gremz:BAABLgAECn8mAAIbAAkJCQrEEABAAQAbAAkJCQrEEABAAQAAAA==.Grozny:BAAALgAECgQJBAAAAA==.Grày:BAABLgAECn8wAAIMAAkJXx2nIQCBAgAMAAkJXx2nIQCBAgAAAA==.',
Gu='Gumboslice:BAACLgAFFH8SAAIEAAYJdg/MJgAmAQAEAAYJdg/MJgAmAQAuAAQKfx8AAgQACQnSHYALAAcDAAQACQnSHYALAAcDAAAA.Gusgus:BAABLgAECn8oAAIFAAgJ5QwfBgBiAQAFAAgJ5QwfBgBiAQAAAA==.',
['Gä']='Gändälf:BAABLgAECn8XAAIjAAgJvxXFBACgAQAjAAgJvxXFBACgAQAAAA==.',
Ha='Habanero:BAABLgAECn8qAAMOAAkJSA+rPAC8AQAOAAkJSA+rPAC8AQAYAAQJUxhuTgD8AAAAAA==.Hachedev:BAAALgAECgMJCAAAAA==.Hadrîan:BAAALgADCgcJCQAAAA==.Hadtopandadk:BAAALgAECgcJDQAAAA==.Hallia:BAACLgAFFH8GAAIEAAMJ9BHjQACtAAAEAAMJ9BHjQACtAAAuAAQKfzgAAgQACQlTGjcTALECAAQACQlTGjcTALECAAAA.Hark:BAAALgADCgkJNwAAAA==.Harrybob:BAAALgADCgcJCgAAAA==.Havvocchi:BAAALgAECgEJAwAAAA==.Hawgwild:BAABLgAECn8lAAIMAAkJJxDNYgCiAQAMAAkJJxDNYgCiAQAAAA==.',
He='Headdinks:BAAALgADCgcJDAAAAA==.Healcap:BAAALgADCgQJBAAAAA==.Healvisprsly:BAABLgAECn8dAAQEAAkJxhgWKgAEAgAEAAgJlxoWKgAEAgADAAYJ9BgHJgCcAQAhAAMJ3hlwMgDfAAAAAA==.Heisenberg:BAAALgADCgMJAwABLgAECgMJBwABAAAAAA==.Helena:BAABLgAECn9EAAMHAAkJFSSKBgA8AwAHAAkJEySKBgA8AwAIAAkJUB5sBQCbAgAAAA==.Heliarc:BAAALgADCgkJOwAAAA==.Hermès:BAAALgAECgUJBgABLgAFFAYJGQAMAOUhAA==.',
Hi='Highfive:BAAALgAECgUJCwAAAA==.',
Ho='Holybeech:BAAALgAECgQJBAAAAA==.Honestly:BAAALgAFFAIJBAAAAA==.Honkytonkman:BAAALgADCgQJBAAAAA==.Hover:BAAALgAECgYJEQAAAA==.',
Ih='Ihmoen:BAAALgADCgYJBgAAAA==.',
Il='Illuminate:BAAALgADCgQJBAAAAA==.Illustria:BAAALgADCgkJKgAAAA==.Illustriâ:BAAALgADCgkJEQABLgADCgkJKgABAAAAAA==.',
Im='Imprison:BAAALgAECgYJBgABLgAECggJGAAFAJUaAA==.',
In='Insidious:BAABLgAECn8fAAIfAAkJFRrLDwAPAgAfAAkJFRrLDwAPAgAAAA==.Invoke:BAAALgADCgEJAQAAAA==.',
Ir='Irs:BAAALgAECgUJBwAAAA==.',
Is='Isisvane:BAAALgAECgQJBgAAAA==.',
It='Itchyfeet:BAAALgAECgUJCAABLgAFFAYJHAAFAFcfAA==.Itchymage:BAACLgAFFH8cAAIFAAYJVx9SOgCBAQAFAAYJVx9SOgCBAQAuAAQKfycAAgUACQnIIzMdAAEDAAUACQnIIzMdAAEDAAAA.Itchyw:BAAALgAFFAEJAQABLgAFFAYJHAAFAFcfAA==.',
Ja='Jacckiemoon:BAAALgAECgQJBAABLgAECgkJHQAEAMYYAA==.Jadehunterr:BAAALgAECgMJBAAAAA==.Jaesn:BAAALgADCgYJBgAAAA==.',
Je='Jenae:BAAALgAECgEJAQAAAA==.Jenövha:BAAALgADCgkJFwAAAA==.Jezebelle:BAAALgAECgUJBQAAAA==.',
Ji='Jighlipuff:BAAALgAECgIJAgAAAA==.Jigs:BAACLgAFFH8FAAIQAAEJOhtsQQBJAAAQAAEJOhtsQQBJAAAuAAQKf0sAAhAACQlNGkQgAGYCABAACQlNGkQgAGYCAAAA.Jiräiya:BAAALgADCgYJBgAAAA==.',
Jo='Johastrasz:BAAALgADCggJCAAAAA==.',
Ju='Junsing:BAAALgADCgEJAQABLgAECggJKgAKAPILAA==.',
['Jå']='Jåfar:BAAALgADCgEJAgAAAA==.',
Ka='Kabøchi:BAAALgAECgUJBQAAAA==.Kafia:BAAALgAECgEJAQAAAA==.Kaladriel:BAAALgADCgEJAQAAAA==.Kaldrick:BAABLgAECn8hAAMYAAkJ4xXoGwACAgAYAAkJZBToGwACAgAZAAEJzhcJCABHAAAAAA==.Kamstareater:BAABLgAECn8mAAIdAAkJ+hLbPgDNAQAdAAkJ+hLbPgDNAQAAAA==.Kanakas:BAABLgAECn8UAAIGAAkJohtXHQAYAgAGAAkJohtXHQAYAgAAAA==.Kanaloa:BAABLgAECn8pAAIFAAkJ1gkKeACJAQAFAAkJ1gkKeACJAQAAAA==.Kayler:BAAALgAECgYJBgABLgAECgYJCwABAAAAAA==.',
Ke='Kegerator:BAAALgAECgUJBgAAAA==.Keirin:BAAALgAECggJEgAAAA==.Keldica:BAAALgAECgIJAgABLgAECgYJFAAFANQfAA==.Kelemver:BAAALgADCgMJAwAAAA==.Kelysa:BAAALgAECggJDwAAAA==.Kena:BAAALgADCgUJBQAAAA==.Kenshan:BAAALgAECgMJAwAAAA==.Kevinbox:BAAALgAECgYJEAAAAA==.Kevinslayer:BAAALgAECgUJDAAAAA==.Keynaridan:BAABLgAECn8ZAAIdAAgJ1xJHVACJAQAdAAgJ1xJHVACJAQAAAA==.Keyss:BAAALgADCgIJAgAAAA==.',
Kg='Kglizard:BAAALgAECgUJCAAAAA==.',
Kh='Khalinor:BAABLgAECn8lAAIGAAkJXhcPEgCCAgAGAAkJXhcPEgCCAgAAAA==.Khardun:BAAALgAECgEJAQAAAA==.Khotuhn:BAAALgAECgMJBgAAAA==.',
Ki='Kickazdin:BAACLgAFFH8LAAIGAAQJShz8GABbAQAGAAQJShz8GABbAQAuAAQKfyIAAwYACQm7HisHABkDAAYACQm7HisHABkDAAcAAgkFCllDAWkAAAAA.Killadragon:BAAALgADCgUJBQAAAA==.Kiryie:BAABLgAECn8bAAIQAAkJDA8cXgCMAQAQAAkJDA8cXgCMAQAAAA==.Kisäme:BAAALgAECggJCwAAAA==.',
Kl='Klad:BAAALgAECgEJAgAAAA==.Klaw:BAAALgADCgkJCQAAAA==.Kluma:BAAALgAECgEJAQAAAA==.',
Kn='Knok:BAAALgAECggJCAAAAA==.',
Ko='Kobu:BAAALgADCgUJBgAAAA==.Konran:BAAALgADCgEJAQAAAA==.',
Kp='Kprist:BAAALgAECgEJAQAAAA==.',
Kr='Kraigen:BAABLgAECn8wAAIcAAkJLh6WBwC3AgAcAAkJLh6WBwC3AgAAAA==.Krinack:BAABLgAECn8kAAIWAAkJXxLGFgDnAQAWAAkJXxLGFgDnAQAAAA==.Krixiz:BAAALgAECgYJCgAAAA==.',
Ks='Kshamify:BAABLgAFFH8HAAIOAAMJzBMuVwCgAAAOAAMJzBMuVwCgAAAAAA==.',
Ku='Kurindrixx:BAAALgADCgIJAgAAAA==.Kurtakum:BAAALgADCgMJAwAAAA==.Kutiel:BAABLgAECn8YAAIYAAcJUgrdUAD0AAAYAAcJUgrdUAD0AAAAAA==.',
Kw='Kwarify:BAAALgADCgEJAQAAAA==.',
Ky='Kynasmira:BAAALgADCgcJHQAAAA==.Kyrsh:BAAALgADCgcJEAAAAA==.',
La='Ladrona:BAABLgAECn8ZAAIkAAkJ+B0lAgDHAgAkAAkJ+B0lAgDHAgAAAA==.Lailyre:BAAALgAECgYJCwAAAA==.Lassan:BAAALgAECgYJCQAAAA==.Later:BAAALgAECggJDAAAAA==.Latimir:BAAALgAECgIJAgAAAA==.Laur:BAAALgADCgYJBgAAAA==.Lavendeer:BAABLgAECn8nAAIDAAkJAhQBHwDQAQADAAkJAhQBHwDQAQAAAA==.Laydin:BAAALgAECgkJCAABLgAECgkJKAAEAMgDAA==.Laylana:BAAALgADCgIJAgABLgADCgUJCQABAAAAAA==.Lazyeye:BAAALgADCgUJBAABLgAECgcJDgABAAAAAA==.',
Lb='Lb:BAAALgADCgUJBgABLgAECgkJFAAYACIZAA==.',
Le='Legume:BAAALgADCgcJCAABLgAECgUJDQABAAAAAA==.Legzanot:BAACLgAFFH8TAAIYAAQJcgoLMgDIAAAYAAQJcgoLMgDIAAAuAAQKfygAAhgACQkyFiQdACgCABgACQkyFiQdACgCAAAA.Leonceault:BAAALgAECgEJAQAAAA==.',
Li='Lifebringa:BAABLgAECn8sAAMUAAgJTh9pCwCwAgAUAAcJ4yJpCwCwAgAiAAcJxhWmJgCXAQAAAA==.Lightningfox:BAABLgAECn8yAAMHAAgJkBqrBQBnAQAHAAgJkBqrBQBnAQAGAAIJug7vdABmAAAAAA==.Lightsfallen:BAAALgAECgkJDwAAAA==.Lileth:BAAALgAECgYJBAAAAA==.Lilylulu:BAAALgADCgIJAgAAAA==.Limzzmagus:BAAALgAECgMJBgAAAA==.Liriel:BAAALgADCgMJAwABLgAECgUJBQABAAAAAA==.Lithia:BAABLgAECn8bAAIMAAkJzw94cgB/AQAMAAkJzw94cgB/AQAAAA==.Littlemo:BAAALgAECgcJEAAAAA==.',
Lo='Loggs:BAAALgAFFAEJAQAAAA==.Lohnar:BAAALgAECgcJEAAAAA==.Lornah:BAAALgADCgQJBAAAAA==.',
Lu='Lucidslock:BAAALgADCgIJAgAAAA==.Lucielbaal:BAABLgAECn8sAAISAAkJ9R4LDwDUAgASAAkJ9R4LDwDUAgAAAA==.Luciferus:BAAALgAECgUJCAABLgAECggJLgATAKcQAA==.Luckystop:BAABLgAECn8ZAAMOAAcJhSJXFACpAgAOAAcJhSJXFACpAgAYAAQJNwqOagCoAAAAAA==.Lumenir:BAAALgAECgEJAQAAAA==.Lunareth:BAAALgAECgQJBAAAAA==.Luraris:BAAALgAECgEJAQAAAA==.',
Ly='Lyrska:BAABLgAECn8vAAITAAkJLRETFAAEAgATAAkJLRETFAAEAgAAAA==.Lytearrow:BAABLgAECn8nAAIQAAgJRA8bYQCEAQAQAAgJRA8bYQCEAQAAAA==.',
['Lè']='Lèonidas:BAAALgAECgEJAgABLgAECgkJLwAhAAMVAA==.',
['Lé']='Léaf:BAAALgAECgMJAwAAAA==.',
Ma='Madfaith:BAAALgADCgEJAQAAAA==.Mahrylee:BAAALgAECgcJEAAAAA==.Maiya:BAAALgADCgcJEAAAAA==.Majutsu:BAAALgADCgEJAQABLgADCgcJDgABAAAAAA==.Malbrax:BAABLgAECn8ZAAISAAgJcxIzVACfAQASAAgJcxIzVACfAQAAAA==.Maleficents:BAABLgAECn8uAAIDAAcJZRN6LgBnAQADAAcJZRN6LgBnAQAAAA==.Malurius:BAABLgAECn8bAAMlAAkJshSzEADoAQAlAAkJsRKzEADoAQACAAYJ4AosZwDBAAAAAA==.Malware:BAAALgAECgYJEQAAAA==.Manana:BAAALgADCgEJAQAAAA==.Manbearpally:BAAALgAECgQJBAAAAA==.Manikfury:BAABLgAECn8iAAMgAAgJwBu6CQAmAgAgAAgJwBu6CQAmAgAEAAYJYx5ZLQDxAQAAAA==.Maniksmage:BAAALgAECggJEgABLgAECggJIgAgAMAbAA==.Mannypack:BAABLgAECn8eAAQDAAgJixwTFQAoAgADAAgJixwTFQAoAgAEAAQJkAz6gQC1AAAhAAEJOxOocAA3AAAAAA==.Maranelli:BAAALgAECgIJAwAAAA==.Maseles:BAAALgAECgUJBgABLgAECgUJCQABAAAAAA==.Maxiticon:BAABLgAECn8XAAQiAAYJTQi8YACWAAAiAAUJ0QW8YACWAAAUAAUJogXVVACJAAAXAAEJnQ73egAwAAAAAA==.',
Mc='Mcdawg:BAAALgADCgYJCgAAAA==.Mcleary:BAAALgAECgYJCQAAAA==.',
Me='Meldrus:BAAALgAECgEJAQAAAA==.Melinashala:BAABLgAECn88AAISAAkJBwWzCwCbAAASAAkJBwWzCwCbAAAAAA==.Mending:BAAALgAECgUJBQAAAA==.Meowinator:BAAALgAECgYJDQAAAA==.Mephizto:BAAALgAECgYJCQAAAA==.Metatrøn:BAAALgAECgYJBwAAAA==.Metide:BAAALgAECgQJBAAAAA==.',
Mi='Miala:BAAALgAECgEJAQAAAA==.Mierna:BAAALgAECgkJEgAAAA==.Miler:BAAALgAECgYJCAAAAA==.Millylittle:BAAALgADCgUJBQAAAA==.Minisor:BAAALgAECgUJBQAAAA==.Misanth:BAAALgAECgYJDgAAAA==.Mistdruid:BAAALgAECgIJAwABLgAECgIJBgABAAAAAA==.',
Mo='Moemo:BAABLgAECn8kAAIEAAkJNSAPCwANAwAEAAkJNSAPCwANAwAAAA==.Mogryn:BAAALgAECgkJEwAAAA==.Moistymists:BAAALgAECgYJCQAAAA==.Moll:BAAALgADCgEJAQAAAA==.Mommybree:BAAALgAECgYJEgAAAA==.Monksterz:BAABLgAECn8wAAIPAAkJayEnBgDaAgAPAAkJayEnBgDaAgAAAA==.Monophobic:BAAALgAECgcJBwAAAA==.Monoxidê:BAAALgAECgEJAQAAAA==.Moonwarriorx:BAAALgAECggJDAAAAA==.Morsecode:BAABLgAECn8hAAILAAkJSRbHCAC+AQALAAkJSRbHCAC+AQABLgABCgIJAgABAAAAAA==.Morthok:BAABLgAECn8rAAISAAgJCBhOOwDtAQASAAgJCBhOOwDtAQAAAA==.Mortischa:BAAALgADCggJCAAAAA==.Mosh:BAABLgAECn8bAAIPAAkJDhQSGgDVAQAPAAkJDhQSGgDVAQAAAA==.',
Mu='Muchuchu:BAAALgAECgUJEQABLgAECgIJAgABAAAAAA==.Muldern:BAAALgAECgEJAQAAAA==.Munkee:BAAALgAECgYJEQAAAA==.Murdinbronze:BAAALgADCgUJCAAAAA==.Mustachekick:BAAALgAECgUJBQAAAA==.Musyl:BAAALgADCgEJAQABLgAECgYJEQABAAAAAA==.',
['Mã']='Mãf:BAABLgAECn8kAAMOAAgJVxH6VABhAQAOAAgJVxH6VABhAQAYAAEJtxx2kABRAAAAAA==.',
['Mí']='Místwalker:BAAALgAECgIJBgAAAA==.',
Na='Nackthyr:BAACLgAFFH8cAAMJAAUJCiYnAQCyAQAJAAUJCiYnAQCyAQAKAAIJNRvOTACbAAAuAAQKfz0AAgkACQmxJkcAAHcDAAkACQmxJkcAAHcDAAAA.Nafir:BAAALgADCgYJFwAAAA==.Nakky:BAAALgAECgYJDgAAAA==.Narlin:BAAALgAECgYJCQAAAA==.Nasta:BAABLgAECn8bAAIHAAYJ6Qhc4QDcAAAHAAYJ6Qhc4QDcAAAAAA==.Natureboi:BAAALgADCgQJBAABLgADCgYJDAABAAAAAA==.Nazareths:BAAALgAECgQJCwAAAA==.Nazgor:BAABLgAECn8VAAIMAAgJ9BaqBgAwAQAMAAgJ9BaqBgAwAQAAAA==.Nazrien:BAAALgADCgMJAwAAAA==.',
Ne='Neckromancy:BAAALgAECgYJCgAAAA==.Necrosius:BAAALgAECgYJDwAAAA==.Neonarc:BAEALgADCgkJLQAAAA==.Neshi:BAAALgAECgMJBQAAAA==.Neuman:BAAALgADCgEJAQAAAA==.',
Ni='Nibblemah:BAAALgAECgcJCwAAAA==.Nightsbane:BAAALgADCgcJEAAAAA==.Nivdk:BAAALgADCgYJBgABLgAECgYJEQABAAAAAA==.Nivora:BAAALgAECgYJEQAAAA==.',
No='Notsure:BAABLgAECn8hAAINAAkJzQXrAwCvAAANAAkJzQXrAwCvAAAAAA==.',
Ny='Nyxstalia:BAAALgAECgUJDAAAAA==.Nyyx:BAABLgAECn8jAAIdAAgJMwg5nQDnAAAdAAgJMwg5nQDnAAAAAA==.',
['Ná']='Nácl:BAAALgAFFAEJAQABLgAFFAUJHAAJAAomAA==.',
Oa='Oath:BAAALgAECgUJBQAAAA==.',
Ob='Obscyra:BAAALgAFFAEJAQAAAA==.',
Ol='Olmek:BAACLgAFFH8eAAICAAgJcRoJCADiAQACAAgJcRoJCADiAQAuAAQKfx4AAgIABwk7JlQPAIACAAIABwk7JlQPAIACAAAA.',
Oo='Oochie:BAAALgADCgQJAwAAAA==.Oonagi:BAAALgAECgUJBQAAAA==.',
Op='Opalana:BAAALgADCgIJAwAAAA==.Ophiana:BAAALgAECgEJAwAAAA==.Oprahwndfury:BAAALgAECgYJDgABLgAECgkJHQAEAMYYAA==.',
Or='Orasaya:BAAALgADCgYJBgAAAA==.Orphee:BAAALgADCgcJBwAAAA==.Orzanis:BAAALgADCgcJDgAAAA==.',
Ow='Owlcapone:BAAALgADCgEJAQAAAA==.',
Pa='Paige:BAAALgADCgcJDgAAAA==.Palasades:BAAALgADCgUJBQAAAA==.Pallymarc:BAAALgADCgcJCwAAAA==.Pallytune:BAACLgAFFH8QAAIGAAMJPxPYLQDDAAAGAAMJPxPYLQDDAAAuAAQKfxwAAgYACQnxDi0lAN0BAAYACQnxDi0lAN0BAAAA.Pandalorian:BAAALgAECgYJEAAAAA==.Pandamajack:BAAALgAECggJEwAAAA==.Paîîy:BAAALgADCgIJAgAAAA==.',
Ph='Philandre:BAABLgAECn8jAAIHAAgJlBNvYgCrAQAHAAgJlBNvYgCrAQAAAA==.',
Pi='Picoso:BAABLgAECn8iAAIFAAkJrw36aQCoAQAFAAkJrw36aQCoAQAAAA==.Piianca:BAAALgAECgUJBgAAAA==.Piianna:BAABLgAECn8ZAAIUAAcJoBucGwDrAQAUAAcJoBucGwDrAQAAAA==.Pirko:BAAALgADCggJCwAAAA==.',
Po='Pocketheal:BAAALgADCgkJEAAAAA==.',
Pr='Probzedgy:BAAALgAECgQJBAAAAA==.',
Pt='Pteradactyl:BAAALgAECgYJBgAAAA==.',
Pu='Punch:BAAALgAECgEJAgAAAA==.Purplerain:BAAALgAECgUJBgAAAA==.Putrigord:BAAALgAECgQJCwAAAA==.',
Py='Pylarthius:BAAALgADCgcJBwAAAA==.',
Qi='Qik:BAAALgAECgEJAQAAAA==.Qikkaw:BAABLgAECn80AAMOAAgJ5hHqBwDvAAAOAAgJ5hHqBwDvAAAYAAcJHQvOBQDPAAAAAA==.Qitetsu:BAAALgAECgUJBgAAAA==.',
Qu='Quantos:BAABLgAECn8/AAIhAAkJrhB8AgA7AQAhAAkJrhB8AgA7AQAAAA==.Ququmatz:BAAALgADCgMJAwAAAA==.',
Ra='Raatha:BAABLgAECn8gAAIHAAkJeRY6NAAvAgAHAAkJeRY6NAAvAgAAAA==.Raeyla:BAAALgAECgcJEwAAAA==.Raganar:BAABLgAECn9DAAIIAAgJrhf4AADFAQAIAAgJrhf4AADFAQAAAA==.Ranlerodis:BAAALgADCgMJAwAAAA==.Rayjean:BAAALgADCgkJIwAAAA==.',
Re='Redneckboots:BAAALgADCgEJAQAAAA==.Relmax:BAABLgAECn8fAAINAAgJKwoFIgAgAQANAAgJKwoFIgAgAQAAAA==.Rendeminae:BAAALgADCgcJBwAAAA==.Renri:BAABLgAECn8eAAIWAAcJFBZUHwCbAQAWAAcJFBZUHwCbAQAAAA==.Repose:BAAALgAECgIJAwAAAA==.Revick:BAAALgAECgUJCAAAAA==.Revil:BAAALgADCgIJAgAAAA==.',
Rh='Rhaenýs:BAAALgADCgcJDQAAAA==.Rhonwynn:BAABLgAECn88AAIOAAgJXB7HAQAiAgAOAAgJXB7HAQAiAgAAAA==.',
Ri='Rikershipdwn:BAABLgAECn8ZAAIQAAgJQRRpTgC3AQAQAAgJQRRpTgC3AQAAAA==.Rikersline:BAAALgADCgkJCQAAAA==.Rimish:BAABLgAECn8cAAMGAAkJDBU8FgBaAgAGAAkJDBU8FgBaAgAHAAEJNRsrIgBQAAAAAA==.Rimrave:BAABLgAECn8qAAQlAAkJnh0IBwCKAgAlAAkJJRwIBwCKAgACAAYJIxscNQDVAQANAAYJiB0LGgBqAQAAAA==.Ripavicii:BAAALgAECgEJAQAAAA==.Ritobeans:BAAALgADCgkJNwAAAA==.Rivik:BAAALgAFFAEJAwAAAA==.',
Ro='Robbstark:BAAALgAECgYJDAAAAA==.Robertkenway:BAABLgAECn8uAAMTAAgJpxChHAC4AQATAAgJpxChHAC4AQAQAAEJAADX1AAwAAAAAA==.Roguebot:BAAALgADCgkJEgAAAA==.Rohdaric:BAABLgAECn8ZAAITAAYJUxTNFgBdAQATAAYJUxTNFgBdAQAAAA==.Rokte:BAABLgAECn8bAAIVAAkJ0w+iDACSAQAVAAkJ0w+iDACSAQAAAA==.Rollhots:BAAALgAECgYJBgAAAA==.Roo:BAAALgAECgEJAwAAAA==.Rook:BAABLgAECn8nAAQLAAgJNyN2BAA2AgASAAgJxCGuFACpAgALAAcJcyB2BAA2AgAVAAEJAAC5SQAAAAABLgAFFAEJAQABAAAAAA==.Rookeh:BAAALgAFFAEJAQAAAA==.Rosekenway:BAABLgAECn81AAMEAAkJ0BfAAAB6AgAEAAkJ0BfAAAB6AgADAAUJ4Qn5aQB5AAABLgAECggJLgATAKcQAA==.',
Rr='Rratt:BAAALgAECgYJDwAAAA==.',
Ru='Rubimoon:BAAALgAECgUJBQAAAA==.Rumí:BAAALgAECggJCAAAAA==.Running:BAAALgAECgIJAgAAAA==.',
Sa='Saammiee:BAAALgAECgMJBAAAAA==.Sabiha:BAABLgAECn8UAAMQAAYJaA+qZQA2AQAQAAYJaA+qZQA2AQAeAAEJwQPplAAlAAAAAA==.Safewaybag:BAAALgADCgQJBAAAAA==.Saintb:BAAALgAECgUJBAAAAA==.Saintotem:BAABLgAECn8lAAIYAAkJYBGeJgC2AQAYAAkJYBGeJgC2AQAAAA==.Samartyr:BAAALgAECgYJCQAAAA==.Samison:BAAALgAECgYJBgAAAA==.Sammiiee:BAAALgADCgQJBAABLgAECgMJBAABAAAAAA==.Sandii:BAAALgADCgkJCgAAAA==.Sangwynaris:BAAALgAECgcJDgAAAA==.Saphiiraa:BAABLgAECn8nAAImAAkJyxEfDgDsAQAmAAkJyxEfDgDsAQAAAA==.Sayahealer:BAAALgADCgcJDgAAAA==.',
Sc='Scorpmage:BAABLgAECn8rAAIFAAgJAhnISQD+AQAFAAgJAhnISQD+AQAAAA==.Scramms:BAAALgADCgcJDQAAAA==.Scrams:BAABLgAECn8VAAIeAAcJpwxdFgAFAQAeAAcJpwxdFgAFAQAAAA==.',
Se='Sedrick:BAABLgAECn9GAAMGAAkJFB6pAABtAgAGAAkJFB6pAABtAgAHAAcJyBW6cgCIAQAAAA==.Sekendipity:BAAALgADCgEJAQABLgAECgcJDgABAAAAAA==.Sekhmett:BAAALgADCgMJAwAAAA==.Sekndestroy:BAAALgADCgYJCQABLgAECgcJDgABAAAAAA==.Sektacular:BAAALgADCgQJBAABLgAECgcJDgABAAAAAA==.Sekzen:BAAALgAECgcJDgAAAA==.Semiazas:BAABLgAECn8/AAQVAAkJsQ+HAADbAQAVAAkJsQ+HAADbAQASAAUJ2QmotwDpAAALAAEJAAD7egAnAAAAAA==.Semiazes:BAAALgADCgYJBgAAAA==.Senessa:BAAALgADCgIJAgAAAA==.Sensy:BAAALgAECgQJCQAAAA==.Sepulveda:BAAALgAECgUJBQABLgAECgkJJAAEADUgAA==.Serwonton:BAAALgADCgUJBQAAAA==.Seumas:BAAALgADCgMJAwAAAA==.',
Sh='Shadrock:BAAALgADCgYJBgAAAA==.Shamtune:BAAALgAECgMJAwABLgAFFAMJEAAGAD8TAA==.Sharayman:BAAALgADCgkJCQABLgADCgkJIwABAAAAAA==.Shattered:BAABLgAECn8hAAIbAAkJxxtNAAB9AgAbAAkJxxtNAAB9AgAAAA==.Shayrisa:BAABLgAECn9AAAMOAAkJTBK6BABVAQAOAAkJTBK6BABVAQAYAAcJ4w4dSQAQAQAAAA==.Shazool:BAABLgAECn8bAAMOAAkJmR7rEgC1AgAOAAkJmR7rEgC1AgAZAAIJkQtPMgBoAAABLgAFFAMJBgAEAPQRAA==.Sheep:BAABLgAECn8YAAMFAAgJlRpsSwD5AQAFAAgJshlsSwD5AQAjAAIJmBkAFABMAAAAAA==.Shifterz:BAAALgAECgcJDwAAAA==.Shrieke:BAAALgAECgYJCQAAAA==.Shrubbery:BAABLgAECn8fAAIhAAgJpBEmHABtAQAhAAgJpBEmHABtAQAAAA==.Shxdow:BAAALgAECgQJBAAAAA==.',
Si='Sind:BAABLgAECn8bAAIIAAgJRhaZDwDKAQAIAAgJRhaZDwDKAQABLgAECgkJLwAhAAMVAA==.Sindella:BAAALgAECgYJDQABLgAECgkJLwAhAAMVAA==.Sinna:BAAALgADCgUJCQAAAA==.Sinthorne:BAABLgAECn8vAAMhAAkJAxX4EQDQAQAhAAgJcxf4EQDQAQAgAAMJ8AW9PQBjAAAAAA==.',
Sk='Skedaddle:BAAALgAECgYJCwABLgAECgkJPwAFAEUkAA==.Skithíryx:BAAALgAECgcJDwAAAA==.Skylight:BAAALgAECgEJAQAAAA==.',
Sl='Slashbndcoot:BAAALgAFFAMJAwAAAA==.Slashgquit:BAACLgAFFH8SAAIfAAQJniDZEwBSAQAfAAQJniDZEwBSAQAuAAQKfzUAAh8ACQmIJOYDAPwCAB8ACQmIJOYDAPwCAAAA.Slumbermist:BAABLgAECn8+AAMnAAkJxhEzHgC8AQAnAAkJxhEzHgC8AQAaAAcJhBJuBQBAAQABLgABCgIJAgABAAAAAA==.',
So='Solaire:BAABLgAECn8hAAMIAAcJWRzfEAC2AQAIAAcJWRzfEAC2AQAGAAUJqRDSTwD6AAABLgAFFAQJCQAnAMQiAA==.Soras:BAAALgADCgkJHwAAAA==.Sourjack:BAAALgAECgUJBgAAAA==.',
St='Steph:BAAALgAECgUJBQAAAA==.',
Su='Sunareas:BAAALgADCgIJAgAAAA==.',
Sy='Syndar:BAAALgAECgEJAQABLgAECgYJFAAFANQfAA==.Synthetic:BAABLgAECn8nAAILAAkJWxYHCADPAQALAAkJWxYHCADPAQAAAA==.Syrebriel:BAAALgADCgEJAgABLgAECgcJGAAYAFIKAA==.',
Sz='Szasstaam:BAABLgAECn8kAAMjAAkJ4wc+BwA9AQAjAAkJ4wc+BwA9AQAFAAQJGQIAJwFsAAAAAA==.',
['Sé']='Sénåtor:BAAALgADCgYJCAABLgAECgkJLwAHAHgUAA==.Séékér:BAAALgADCgcJFQAAAA==.',
Ta='Talanith:BAAALgADCggJEAAAAA==.Tarayk:BAAALgADCgYJCAABLgADCgkJIwABAAAAAA==.Taxal:BAAALgADCgYJBwAAAA==.Taxlock:BAABLgAECn8aAAISAAcJ9wmGmwAGAQASAAcJ9wmGmwAGAQAAAA==.',
Tb='Tbagjones:BAAALgAECgQJBAAAAA==.',
Te='Tecsaran:BAABLgAECn8UAAIFAAYJ1B/ebgD2AQAFAAYJ1B/ebgD2AQAAAA==.Tekis:BAAALgADCgEJAQAAAA==.Telz:BAAALgAECgYJCgAAAA==.Terania:BAAALgADCgIJAgAAAA==.',
Th='Thalira:BAABLgAECn8dAAQmAAgJQAfpGwAgAQAmAAgJQAfpGwAgAQAKAAcJTwIocACLAAAJAAQJrQGENQBpAAAAAA==.',
Ti='Tibbz:BAAALgADCgIJAgAAAA==.Tiger:BAACLgAFFH8+AAQgAAkJECUBAACwAwAgAAkJECUBAACwAwAhAAQJiCLVDAArAQAEAAMJYhpwMwDgAAAuAAQKfyoAAyAACQnqJgUAABYEACAACQnqJgUAABYEAAQAAQm1C4TEAD8AAAAA.Tinkera:BAAALgAECgQJBAAAAA==.Tinnea:BAAALgAECgUJDgAAAA==.Titanosaurus:BAAALgAECgcJEAAAAA==.Tizzly:BAABLgAECn8rAAIFAAkJzQ5vagCnAQAFAAkJzQ5vagCnAQAAAA==.',
To='Torhilda:BAAALgAECgYJBgABLgAECgYJFAAFANQfAA==.Torridwells:BAABLgAECn8bAAIQAAkJdA/RWgCVAQAQAAkJdA/RWgCVAQAAAA==.',
Tr='Trad:BAAALgADCgYJBgAAAA==.Troag:BAABLgAECn8fAAIOAAkJcRz1GgBzAgAOAAkJcRz1GgBzAgAAAA==.Troagstar:BAABLgAECn8nAAIYAAkJChvlGwACAgAYAAkJChvlGwACAgAAAA==.',
Ts='Tsaesci:BAAALgADCgQJBgAAAA==.Tsynn:BAAALgADCgYJFAAAAA==.',
Ty='Tylerz:BAAALgAFFAEJAQAAAA==.Tyraana:BAACLgAFFH8IAAIcAAMJrxhdBQDpAAAcAAMJrxhdBQDpAAAuAAQKf0IAAxwACQlPIJEFAOcCABwACQlPIJEFAOcCAB0ACAndFGVMAKABAAAA.Tyrinwar:BAAALgADCgYJDAAAAA==.Tyrmog:BAABLgAECn8eAAIMAAkJHAl/lgA7AQAMAAkJHAl/lgA7AQAAAA==.Tytus:BAAALgAECgUJBQAAAA==.',
Un='Unique:BAAALgAECgEJAQABLgAFFAYJGwACADkkAA==.',
Us='Ushas:BAABLgAECn8yAAMUAAkJChmrGQD+AQAUAAkJChmrGQD+AQAXAAQJqQXgWwCQAAAAAA==.Usmcshammy:BAAALgAECgUJDAAAAA==.',
Va='Vali:BAABLgAECn8sAAIeAAkJHB/vAgCyAgAeAAkJHB/vAgCyAgAAAA==.Valindrea:BAAALgAECgcJEAAAAA==.Vasrael:BAABLgAECn82AAMHAAkJshd3OwAWAgAHAAgJ/Bl3OwAWAgAGAAcJYRzcHQAUAgAAAA==.Vav:BAABLgAECn8UAAMQAAYJeBdqoQD/AAAQAAYJeBdqoQD/AAATAAIJswzTYAA5AAAAAA==.',
Ve='Vecnis:BAAALgAECgIJAgAAAA==.Veliette:BAAALgAECgUJBwAAAA==.Verdena:BAAALgADCgcJBwABLgADCgkJIwABAAAAAA==.Vexen:BAABLgAECn8dAAIdAAkJ6BLGAQDiAQAdAAkJ6BLGAQDiAQAAAA==.',
Vi='Victaliste:BAAALgAECgQJBQAAAA==.Vithper:BAAALgAECggJEwAAAA==.',
Vn='Vnia:BAAALgADCgMJAwABLgAECgMJCAABAAAAAA==.',
Vo='Voidmuffinz:BAACLgAFFH8IAAIdAAMJ4gz0agC2AAAdAAMJ4gz0agC2AAAuAAQKfyMAAh0ACQkmGE4tABICAB0ACQkmGE4tABICAAAA.',
Vy='Vynis:BAAALgAECgcJDQABLgAFFAMJEAAGAD8TAA==.Vyrahildard:BAABLgAECn8tAAIHAAkJfRuWJwBlAgAHAAkJfRuWJwBlAgAAAA==.',
Wa='Wakkiq:BAAALgAECgEJAQAAAA==.Waringoutlaw:BAABLgAECn8UAAICAAcJYgGangA3AAACAAcJYgGangA3AAAAAA==.Wasteland:BAABLgAECn8rAAIfAAkJphEvGwCDAQAfAAkJphEvGwCDAQAAAA==.',
We='Weaselhunter:BAAALgAFFAIJAgABLgAFFAIJBgASAPAWAA==.Weasellock:BAABLgAFFH8GAAISAAIJ8BYikgCeAAASAAIJ8BYikgCeAAAAAA==.Weaselmage:BAAALgAFFAIJAgABLgAFFAIJBgASAPAWAA==.Welor:BAAALgADCgYJDAAAAA==.',
Wh='Whatthef:BAAALgAECggJCwAAAA==.',
Wi='Wildweasel:BAAALgAFFAIJAwABLgAFFAIJBgASAPAWAA==.Winterhide:BAABLgAECn8xAAIMAAkJoxnBIwB2AgAMAAkJoxnBIwB2AgAAAA==.',
Wo='Wolfe:BAAALgADCgIJAgAAAA==.',
Xa='Xallie:BAECLgAFFH8GAAIdAAMJaQgQcACpAAAdAAMJaQgQcACpAAAuAAQKfz8AAh0ACQl8GoUgAFECAB0ACQl8GoUgAFECAAAA.Xanvyr:BAABLgAECn8hAAIHAAkJXxk8PwAJAgAHAAkJXxk8PwAJAgAAAA==.Xaquillis:BAACLgAFFH8TAAMRAAQJVwvUBQDOAAARAAQJKwrUBQDOAAAMAAMJuQ0ytQC8AAAuAAQKfyYAAwwACQkuGyc8AEcCAAwACAmZGyc8AEcCABEABAmwFr0VACsBAAAA.Xarthis:BAAALgAECgEJAQABLgAFFAQJEwARAFcLAA==.',
Xe='Xentrie:BAAALgADCgUJCgAAAA==.Xeyvara:BAABLgAECn8sAAIbAAkJoCTaAABCAwAbAAkJoCTaAABCAwAAAA==.',
Xg='Xg:BAAALgADCgUJBgABLgAECgYJJgAYALwfAA==.',
Xi='Xindra:BAAALgAECgkJCQAAAA==.',
Ya='Yamiyugi:BAAALgAECgEJAQAAAA==.Yatsui:BAAALgAECgQJBAAAAA==.',
Yo='Youngthug:BAAALgAECgIJAwAAAA==.',
Yu='Yutaa:BAAALgADCgYJBgAAAA==.',
Za='Zaden:BAAALgAECgYJBwAAAA==.Zangi:BAAALgAECgEJAgABLgAECgkJLAAEAL4hAA==.Zarihanna:BAABLgAECn84AAIFAAgJ0hcqBQCGAQAFAAgJ0hcqBQCGAQAAAA==.Zatannah:BAAALgADCgUJBQAAAA==.',
Ze='Zedryn:BAABLgAECn8nAAISAAkJew92RwDDAQASAAkJew92RwDDAQAAAA==.Zenshi:BAAALgAECgEJAgAAAA==.Zeperios:BAAALgAECgYJCgAAAA==.Zeril:BAABLgAECn8UAAMVAAgJjReLDACTAQAVAAgJjReLDACTAQASAAEJHgXrVwEoAAAAAA==.Zestdruid:BAAALgAECggJEQAAAA==.Zestull:BAABLgAECn8lAAIPAAgJnCS2BgDOAgAPAAgJnCS2BgDOAgAAAA==.Zetsuboiki:BAAALgADCgcJBwAAAA==.Zetsudeath:BAAALgADCgYJBgAAAA==.',
Zh='Zhoel:BAAALgADCgEJAQAAAA==.',
Zi='Ziak:BAAALgAECgUJBQAAAA==.Zindeshal:BAAALgAECgYJCQAAAA==.',
Zo='Zorc:BAACLgAFFH8WAAIYAAUJhBcqGwBBAQAYAAUJhBcqGwBBAQAuAAQKfycAAhgACQmKIPsJAPQCABgACQmKIPsJAPQCAAAA.',
Zu='Zunji:BAAALgAECgEJBAAAAA==.',
Zy='Zyate:BAABLgAECn8xAAISAAkJTRJdRwDEAQASAAkJTRJdRwDEAQAAAA==.Zyrryn:BAABLgAECn8XAAIJAAgJwQOXEgDhAAAJAAgJwQOXEgDhAAAAAA==.',
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
