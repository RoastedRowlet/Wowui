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

local lookup = {'Unknown-Unknown','Warrior-Fury','Druid-Balance','Druid-Restoration','Rogue-Assassination','Mage-Frost','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Evoker-Devastation','Evoker-Augmentation','Warlock-Destruction','DeathKnight-Unholy','Warrior-Protection','Shaman-Restoration','Monk-Brewmaster','Hunter-BeastMastery','DeathKnight-Frost','Monk-Windwalker','Warlock-Demonology','Hunter-Survival','Priest-Holy','Warlock-Affliction','Rogue-Subtlety','Priest-Discipline','Priest-Shadow','Shaman-Elemental','Shaman-Enhancement','Monk-Mistweaver','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Marksmanship','DeathKnight-Blood','Druid-Feral','Druid-Guardian','Mage-Arcane','Warrior-Arms','Evoker-Preservation',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=46,date='2026-08-11',data={Aa='Aaffoxx:BAAALgAECgEJAQAAAA==.Aagonyy:BAAALgAECgEJBQAAAA==.',
Ae='Aenninicus:BAAALgAECgEJAgAAAA==.Aernoth:BAAALgAECgUJDQAAAA==.',
Af='Affox:BAAALgAECgEJAQAAAA==.',
Ak='Akaidia:BAAALgAECgYJBgABLgAECgkJAwABAAAAAA==.',
Al='Alderan:BAABLgAECn8lAAICAAcJIg4dQwA5AQACAAcJIg4dQwA5AQAAAA==.Aleinas:BAABLgAECn8kAAMDAAcJKxbLMwBKAQADAAcJKxbLMwBKAQAEAAQJQQixlQCIAAAAAA==.Alektophobia:BAABLgAECn8UAAIFAAkJmRE4EAAhAQAFAAkJmRE4EAAhAQAAAA==.Alendra:BAAALgAECgEJAQABLgAECgkJLAAGACoiAA==.Alluisice:BAAALgAECgYJBgAAAA==.Allysaun:BAAALgAECgUJBgAAAA==.Alpharoach:BAAALgADCgYJBgAAAA==.Alufina:BAAALgAECgYJBgABLgAECgkJHAAHAAkVAA==.Alzeinrich:BAABLgAECn8YAAMIAAcJSQd93gDgAAAIAAcJmgV93gDgAAAJAAQJbwjJNwCAAAAAAA==.',
Am='Amorina:BAABLgAECn8dAAIIAAkJUBepVQDKAQAIAAkJUBepVQDKAQAAAA==.',
An='Anarii:BAAALgAECgIJAgAAAA==.Anda:BAAALgAECgMJAwAAAA==.Andarnn:BAAALgAECgEJAQAAAA==.Andracca:BAABLgAECn8eAAMKAAkJFAspDABOAQAKAAkJFAspDABOAQALAAEJQAXynAAkAAAAAA==.Andromeda:BAABLgAECn8XAAIEAAkJWwzzTwBPAQAEAAkJWwzzTwBPAQAAAA==.Aner:BAAALgAECgEJBwAAAA==.Angrygnome:BAACLgAFFH8JAAIMAAMJex44CAAUAQAMAAMJex44CAAUAQAuAAQKfx4AAgwACQmqILoBAL4CAAwACQmqILoBAL4CAAAA.Angélique:BAAALgAFFAIJAwABLgAFFAgJIgANAFYiAA==.Antcension:BAAALgADCgUJBQAAAA==.Antemental:BAAALgAECgYJEAAAAA==.Anthigos:BAAALgAECgMJAwAAAA==.',
Ar='Arax:BAABLgAECn8dAAIOAAcJ7yHTDgD9AQAOAAcJ7yHTDgD9AQAAAA==.Arcada:BAAALgAECgUJBQABLgAECgUJBQABAAAAAA==.Arcaidious:BAAALgAECgUJCgABLgAECggJJAAPAFcRAA==.Arcamoon:BAAALgAECgIJAgABLgAECgUJBQABAAAAAA==.Arcashi:BAAALgADCgcJCgABLgAECgUJBQABAAAAAA==.Arcxdd:BAAALgAECgQJBAAAAA==.Areuawizard:BAAALgAECgYJBgAAAA==.Arianlion:BAAALgAECgQJBQAAAA==.Ariantheone:BAAALgAECgEJAQAAAA==.Armistice:BAAALgAECgEJAgAAAA==.Arowenn:BAAALgADCgMJAwAAAA==.Arrokoth:BAAALgAECgkJDgAAAA==.Artana:BAAALgAECgIJAgAAAA==.Artistic:BAAALgAECgUJBQAAAA==.',
As='Ashad:BAAALgAECgQJBwAAAA==.Askook:BAABLgAECn8aAAIKAAkJ0AatAwDJAAAKAAkJ0AatAwDJAAAAAA==.Astolvik:BAAALgAECgQJBgAAAA==.',
At='Athurnz:BAAALgAECgkJEwAAAA==.Attachedplag:BAAALgAFFAEJAQAAAA==.Atulwa:BAABLgAECn82AAIPAAkJQxqWBQAaAgAPAAkJQxqWBQAaAgAAAA==.',
Au='Aurinox:BAABLgAECn8dAAIGAAYJ9w4HugATAQAGAAYJ9w4HugATAQAAAA==.Auriol:BAAALgADCgcJBwAAAA==.Autodrive:BAABLgAECn8eAAIQAAkJXhw5AQBrAgAQAAkJXhw5AQBrAgAAAA==.',
Av='Avralea:BAABLgAECn9PAAIQAAgJJBzOEgAdAgAQAAgJJBzOEgAdAgAAAA==.',
Az='Azenthal:BAAALgAECgEJAQAAAA==.Azurestrider:BAAALgAECgEJAQAAAA==.',
['Aç']='Açhilles:BAAALgAECgYJCAABLgAECgkJHQAEAN4YAA==.',
Ba='Baconinja:BAAALgAECgEJAQAAAA==.Bananahammik:BAAALgAECgYJDgAAAA==.Banzen:BAABLgAECn8yAAIRAAkJhxOpCQDiAQARAAkJhxOpCQDiAQAAAA==.Barghest:BAAALgADCgMJAwAAAA==.Basz:BAACLgAFFH8QAAINAAQJthEiQQDbAAANAAQJthEiQQDbAAAuAAQKf0oAAw0ACQknHngFADMCAA0ACQknHngFADMCABIABwlvFXsFABwBAAAA.Battle:BAEALgAECgEJAgABLgAFFAIJBgATAL4hAA==.',
Be='Beefburglar:BAAALgAECgYJBgAAAA==.Beginagain:BAAALgAECgEJAQAAAA==.Belfias:BAAALgAECgEJAgABLgAECgkJIwASAKccAA==.Belgran:BAABLgAECn8jAAISAAkJpxxzAQBKAgASAAkJpxxzAQBKAgAAAA==.Belmonte:BAAALgADCgEJAQAAAA==.Belris:BAAALgAECgQJBAAAAA==.Berunma:BAABLgAECn8hAAIRAAkJexaOBwAVAgARAAkJexaOBwAVAgAAAA==.Betabill:BAAALgAECgUJBQAAAA==.',
Bh='Bhain:BAABLgAECn8hAAMUAAcJ5R3lSgDpAQAUAAcJ5R3lSgDpAQAMAAEJaA2FdAAwAAABLgAFFAUJGgAIAKwfAA==.',
Bi='Bileshots:BAABLgAECn8VAAIVAAkJTRciHAC8AQAVAAkJTRciHAC8AQAAAA==.Biowolf:BAACLgAFFH8wAAIGAAYJpwmUKgAmAQAGAAYJpwmUKgAmAQAuAAQKfywAAgYACQneFBVEAA8CAAYACQneFBVEAA8CAAAA.Birdhunter:BAAALgAFFAEJAQAAAA==.Bishopixixix:BAAALgAECgYJCwABLgAECgcJDwABAAAAAA==.Bits:BAABLgAECn8rAAIUAAkJWgfecwBSAQAUAAkJWgfecwBSAQAAAA==.',
Bj='Bjoren:BAABLgAECn8wAAIWAAkJGyRSAwBcAwAWAAkJGyRSAwBcAwAAAA==.',
Bl='Blackdread:BAAALgADCgYJBgAAAA==.Blasterjenny:BAAALgAECgYJCAAAAA==.Bloodcaptain:BAABLgAECn8cAAMMAAkJORfuBgDtAQAMAAkJZBbuBgDtAQAXAAYJshf6CAC3AQAAAA==.',
Bo='Bohma:BAAALgADCgEJAQAAAA==.Boopblast:BAAALgAECgUJDQAAAA==.Bootiebang:BAABLgAECn8XAAIYAAcJbQSoOgDjAAAYAAcJbQSoOgDjAAAAAA==.Bootieknight:BAAALgAECgUJCwAAAA==.Bootycaall:BAAALgAECgEJAQAAAA==.Bootycall:BAAALgAECgUJCgAAAA==.Boroth:BAAALgADCgcJBwAAAA==.',
Br='Breetech:BAAALgAECgIJAgAAAA==.Brett:BAAALgAECgEJAQAAAA==.Breé:BAAALgAECgEJAQAAAA==.Brianx:BAAALgADCgIJAgAAAA==.Brklyn:BAAALgAFFAEJAQAAAA==.Brockshot:BAAALgAECgUJBQAAAA==.Brokki:BAAALgADCgEJAQAAAA==.',
Bu='Buckaroo:BAAALgAECgQJBQAAAA==.Bucknastey:BAAALgAECgIJAgAAAA==.Bucknekkid:BAABLgAECn8UAAIIAAkJqQWyyAD9AAAIAAkJqQWyyAD9AAAAAA==.Buckwhild:BAABLgAECn8uAAQZAAgJZSI2AwA1AgAWAAgJZyEzCQDWAgAZAAYJ7R82AwA1AgAaAAUJxBhMCgAfAQAAAA==.Burrhus:BAAALgAECgQJBAAAAA==.',
Ca='Cagomei:BAAALgADCggJDgAAAA==.Caladbolg:BAACLgAFFH8FAAMJAAIJYRc/CQCIAAAJAAIJYRc/CQCIAAAIAAIJmQPFZwBJAAAuAAQKf1gAAwkACAntIu8AAKkCAAkACAntIu8AAKkCAAgAAwmwGosvAJgAAAAA.Camrillem:BAAALgAFFAEJAQAAAA==.Cannacola:BAABLgAECn8mAAMbAAYJvB/KKwCXAQAcAAYJ1BzoDQDeAQAbAAYJOh7KKwCXAQAAAA==.Carebearr:BAAALgAECgMJAwAAAA==.',
Ce='Cearius:BAAALgAECgYJCgABLgAFFAYJFQAUAEweAA==.Celthis:BAAALgADCgcJBwABLgAECgUJCQABAAAAAA==.Cerdwin:BAAALgAECgEJAQABLgAECgkJLAAGACoiAA==.Cesàrè:BAABLgAECn8lAAIdAAkJCQwgEgANAQAdAAkJCQwgEgANAQAAAA==.',
Ch='Chahra:BAABLgAECn8bAAIeAAkJyw1aEABHAQAeAAkJyw1aEABHAQAAAA==.Chammie:BAAALgAECgYJBgAAAA==.Chamuki:BAACLgAFFH8GAAMfAAMJ4g8/IgCJAAAfAAIJZhY/IgCJAAAgAAEJ2wKkpwAyAAAuAAQKfy0ABB8ACAn0He8OADcCAB8ABwkNIe8OADcCACAABQm2DcK5ALgAAB4ABAkUHnMGAKoAAAEuAAUUCAkdAAMAhxsA.Chaosbolt:BAACLgAFFH8HAAIUAAMJwAbuTwBhAAAUAAMJwAbuTwBhAAAuAAQKfxMAAhQACAmCGN8EABECABQACAmCGN8EABECAAAA.Cheesecake:BAACLgAFFH8iAAMNAAgJViJGFADLAQANAAgJViJGFADLAQASAAQJSRQjDADaAAAuAAQKfykAAw0ACQl+JcQCAK4DAA0ACQl+JcQCAK4DABIAAwn1G+EmAJwAAAAA.Cheesecaké:BAAALgAFFAIJAgABLgAFFAgJIgANAFYiAA==.Cheesuspiece:BAAALgADCgIJAgAAAA==.Chrispbacon:BAAALgAECgMJBAAAAA==.Chuubak:BAAALgAECgkJBwAAAA==.',
Cl='Clangeddin:BAAALgAECgQJBAAAAA==.Clangedin:BAABLgAECn8zAAICAAkJUwyjCQA0AQACAAkJUwyjCQA0AQAAAA==.',
Co='Cobalt:BAAALgADCgUJBQABLgAFFAUJDwAUAFYaAA==.Colonidus:BAAALgAECgEJAQAAAA==.Coondic:BAAALgADCgEJAQAAAA==.Coreydruid:BAAALgAECgMJBwAAAA==.Coreypala:BAAALgAECgIJBAAAAA==.Coreysham:BAAALgAECgQJBQAAAA==.Corily:BAAALgADCgcJHAAAAA==.Corsten:BAABLgAECn84AAIOAAgJDhO2AwCPAQAOAAgJDhO2AwCPAQAAAA==.Cosmictonic:BAAALgADCgYJBgAAAA==.Cotija:BAAALgADCgkJCQAAAA==.',
Cr='Crabpack:BAAALgADCgIJAgAAAA==.Crayoneater:BAAALgAECgQJBAAAAA==.Crippleswagg:BAAALgAECgYJAQAAAA==.Croisades:BAAALgAECgQJCgAAAA==.Crosis:BAAALgADCgcJFwAAAA==.Crowmatic:BAABLgAECn8aAAINAAkJ+h5fJwBlAgANAAkJ+h5fJwBlAgAAAA==.Crusadan:BAAALgADCgYJBgAAAA==.Cryo:BAAALgAECgEJAQAAAA==.',
Cu='Cucklizard:BAAALgAECgEJAQAAAA==.Cute:BAABLgAFFH8NAAICAAMJNCOSKAATAQACAAMJNCOSKAATAQAAAA==.',
['Cà']='Càhos:BAAALgADCgUJBQAAAA==.',
Da='Dagby:BAAALgADCgEJAQAAAA==.Dakon:BAABLgAECn83AAMJAAkJThoNCgArAgAJAAkJThoNCgArAgAIAAIJcBi7DAF9AAAAAA==.Dalune:BAABLgAECn8/AAIbAAkJOg0rCABXAQAbAAkJOg0rCABXAQAAAA==.Daneaus:BAABLgAECn8sAAIEAAkJviH0BQBZAwAEAAkJviH0BQBZAwAAAA==.Daniellson:BAACLgAFFH8HAAIVAAMJ1g1YIQDOAAAVAAMJ1g1YIQDOAAAuAAQKfxgABCEACAkoEesvALUBACEACAkoEesvALUBABUAAQk+EKFhADgAABEAAQkAAFrcABcAAAEuAAUUCAkeABMA9R4A.Danon:BAAALgADCgEJAQAAAA==.Daredevil:BAAALgAECgYJCQABLgAECggJFwANALYcAA==.Dargonath:BAAALgAFFAEJAwAAAA==.Darkchronos:BAAALgAECgEJAgAAAA==.Darkehawke:BAAALgAECgEJAQAAAA==.Darkscorp:BAAALgADCgkJEAAAAA==.Darkwolf:BAACLgAFFH8RAAINAAQJZAo0OgDwAAANAAQJZAo0OgDwAAAuAAQKf0IAAw0ACQkXFS83ACICAA0ACQkXFS83ACICACIACAn+C/ELALUAAAAA.Darnuus:BAAALgAFFAIJAgAAAA==.Datromandude:BAAALgAECgYJCgAAAA==.Dawnbringer:BAAALgADCgQJBAAAAA==.',
Db='Dblaster:BAAALgAECgUJCwAAAA==.',
De='Deathbydruid:BAABLgAECn8oAAMEAAkJyANFfwC8AAAEAAkJyANFfwC8AAADAAYJ1QCEfwBJAAAAAA==.Deathkweasel:BAAALgAECgMJAwABLgAFFAMJBAABAAAAAA==.Deathnelf:BAABLgAECn8bAAQSAAkJ7AnKFgAiAQASAAgJAgvKFgAiAQANAAYJYQXU8gC9AAAiAAIJQwOmGQA5AAAAAA==.Deazraelle:BAACLgAFFH8IAAIUAAMJtRPXMADDAAAUAAMJtRPXMADDAAAuAAQKfyIAAhQACAnkH/kDAEICABQACAnkH/kDAEICAAAA.Decimator:BAAALgADCggJHwAAAA==.Declan:BAAALgADCgUJBQAAAA==.Dedric:BAABLgAECn8nAAQjAAgJ8wqDIwDuAAAjAAgJGwiDIwDuAAADAAgJKgRJTgDTAAAkAAEJNRcqbAA+AAAAAA==.Deesis:BAAALgADCgEJAQAAAA==.Dellin:BAABLgAECn8qAAIDAAkJFBcgGAAMAgADAAkJFBcgGAAMAgAAAA==.Demeco:BAEBLgAFFH8nAAMIAAkJpRu5BQBLAgAIAAcJzh+5BQBLAgAHAAgJ3hP7AwBCAgABLgAFFAkJLgAHAAIeAA==.Demonch:BAAALgAECgUJCAAAAA==.Demonweasel:BAAALgAFFAIJAwABLgAFFAMJBAABAAAAAA==.Depeche:BAABLgAECn8fAAIgAAcJGBK+mgDrAAAgAAcJGBK+mgDrAAAAAA==.Deralle:BAABLgAECn8sAAILAAkJSQzMOQBFAQALAAkJSQzMOQBFAQABLgAFFAIJAgABAAAAAA==.Dethrift:BAAALgAECgEJAQAAAA==.Devildognutz:BAAALgAECgQJBAAAAA==.',
Di='Dil:BAAALgAECgIJAwABLgAECggJGAAGAJUaAA==.Diminuendo:BAAALgAECgcJEAAAAA==.',
Dj='Djenu:BAAALgAECggJCAAAAA==.',
Do='Doctrwho:BAAALgAECgcJAQAAAA==.Donalda:BAAALgAECgEJAQAAAA==.Dorillion:BAAALgAECgUJCQAAAA==.Dorozh:BAABLgAECn8hAAIMAAkJHBbvCQCnAQAMAAkJHBbvCQCnAQAAAA==.',
Dr='Draconx:BAAALgADCgYJBgAAAA==.Draghr:BAAALgAECgQJBAAAAA==.Dragonzmage:BAAALgAECgMJAwAAAA==.Dragskar:BAAALgADCgUJBQAAAA==.Drala:BAABLgAECn8kAAMZAAkJ2xToFwAVAgAZAAkJ2xToFwAVAgAWAAEJ2w77ggAuAAAAAA==.Dreadmage:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.Dreadpally:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Dreadsham:BAAALgADCgIJAgABLgAECgEJAQABAAAAAA==.Dreco:BAAALgADCgcJBwAAAA==.Driver:BAEBLgAFFH8FAAIIAAIJSR2RgQCyAAAIAAIJSR2RgQCyAAABLgAFFAUJEQAUALYLAA==.Dryconias:BAACLgAFFH8RAAIIAAMJvBZMNgC7AAAIAAMJvBZMNgC7AAAuAAQKfzkAAwgACQkQIKYhAIACAAgACQkQIKYhAIACAAkAAQmfCNBUACcAAAAA.Drèadpriest:BAABLgAECn8VAAQZAAUJwR2JJQCjAQAZAAUJux2JJQCjAQAWAAUJ0hR9QgDhAAAaAAIJCRMGUQCJAAAAAA==.Drôgô:BAABLgAECn8VAAIRAAYJnhM7TgB+AQARAAYJnhM7TgB+AQABLgAECggJCAABAAAAAA==.',
Du='Dunkelzhan:BAABLgAECn9iAAIGAAkJdB+pAwC9AgAGAAkJdB+pAwC9AgAAAA==.Duntack:BAAALgADCgEJBAAAAA==.',
Dy='Dyana:BAABLgAECn8hAAIRAAkJohVJRgDPAQARAAkJohVJRgDPAQAAAA==.',
Dz='Dz:BAACLgAFFH8NAAMHAAQJhRkuIAAcAQAHAAQJhRkuIAAcAQAIAAQJPwmwVgACAQAuAAQKf0UAAwcACQlBJlsAAN8DAAcACQlBJlsAAN8DAAgABQlHD6b4AMAAAAAA.',
['Dø']='Dømimømmÿ:BAAALgAECgUJCAAAAA==.',
Ea='Earts:BAAALgAECgYJBgAAAA==.',
Ec='Ecowolf:BAAALgADCgkJDwABLgADCgkJPQABAAAAAA==.',
Ed='Edgyname:BAABLgAECn8UAAIgAAcJBCASMwD5AQAgAAcJBCASMwD5AQAAAA==.Edgyvoid:BAAALgADCgYJDAAAAA==.Edlund:BAABLgAECn8jAAIKAAkJfQ1jCACqAQAKAAkJfQ1jCACqAQAAAA==.Edram:BAAALgAECgIJAgAAAA==.',
Ef='Effyinzpjake:BAAALgAECgYJDgAAAA==.',
Ei='Eianistic:BAAALgAFFAIJAgAAAA==.',
El='Elbiee:BAAALgAECggJCAABLgAECgkJFAAbACIZAA==.Eleos:BAAALgAECgYJDAAAAA==.Elfvispresly:BAAALgAECgEJAQABLgAECgkJDwABAAAAAA==.Ellenee:BAAALgADCgMJAwAAAA==.Ellinor:BAAALgADCgkJPQAAAA==.Elvy:BAABLgAECn8wAAIDAAkJNxkbGgD7AQADAAkJNxkbGgD7AQAAAA==.',
En='Enngin:BAABLgAFFH8HAAIlAAQJOBE1AwCyAAAlAAQJOBE1AwCyAAAAAA==.Enragee:BAAALgAECgEJAwABLgAECgcJGQAPAIUiAA==.Enroks:BAAALgAECgUJBQAAAA==.',
Er='Erebus:BAAALgAECgYJDAAAAA==.Erythra:BAAALgAECgQJBAAAAA==.',
Eu='Euphoría:BAAALgADCgIJAgAAAA==.',
Ev='Evildefiant:BAAALgAECgEJAQAAAA==.Evilfoxx:BAAALgADCgQJBQAAAA==.',
Ex='Exsalsior:BAAALgADCgYJBgAAAA==.',
Ey='Eyedoc:BAAALgADCgQJBAAAAA==.',
Fa='Fabulousness:BAABLgAECn8vAAIWAAkJCiHoBAAxAwAWAAkJCiHoBAAxAwAAAA==.',
Fe='Fearliz:BAAALgADCgEJAQAAAA==.Felmina:BAAALgADCgkJCQAAAA==.',
Fi='Fifefrost:BAAALgAECgQJBAAAAA==.Fishingsucks:BAAALgAECgcJCgAAAA==.Fistery:BAAALgADCgkJCQAAAA==.Fiurich:BAAALgAFFAEJAQAAAA==.',
Fl='Flexi:BAAALgADCgEJAQAAAA==.Flitred:BAAALgAECggJDwAAAA==.Flock:BAABLgAECn8cAAINAAcJJRhCDgBTAQANAAcJJRhCDgBTAQAAAA==.',
Fo='Forq:BAAALgAECgEJAQAAAA==.Foxx:BAAALgAECgUJDQAAAA==.',
Fr='Framboise:BAABLgAECn8ZAAICAAYJUQcaYAAwAQACAAYJUQcaYAAwAQAAAA==.Frostybolt:BAAALgAECgUJBwAAAA==.',
Fu='Furryosa:BAAALgADCgUJBQAAAA==.Furryriver:BAAALgAECgcJEAAAAA==.Furytotem:BAABLgAECn8XAAIbAAgJiBPSBQCeAQAbAAgJiBPSBQCeAQABLgAECgEJAQABAAAAAA==.',
['Fø']='Føxx:BAAALgAECgEJAQAAAA==.',
Ga='Galadhras:BAAALgADCgkJIAAAAA==.Galdryn:BAAALgADCgIJAQAAAA==.Galianna:BAABLgAECn8YAAIWAAkJtBE1IQC5AQAWAAkJtBE1IQC5AQAAAA==.Gamboslice:BAACLgAFFH8LAAISAAUJqgwKCgD7AAASAAUJqgwKCgD7AAAuAAQKfx8AAhIACQn+FigEAE4BABIACQn+FigEAE4BAAAA.Garkevon:BAAALgAECggJBwAAAA==.',
Ge='Gemeni:BAAALgAECgEJAQAAAA==.Gevul:BAACLgAFFH8QAAMUAAYJ3QwuJgD3AAAUAAUJ3QwuJgD3AAAXAAIJcgqKFgBGAAAuAAQKf2sAAxQACQnyG6YZAIoCABQACQnfG6YZAIoCAAwABAnlEwMkAJIAAAAA.',
Gh='Ghostess:BAAALgADCgkJAQAAAA==.Ghrank:BAABLgAECn8pAAQUAAgJ8Q+/CQBpAQAUAAgJ8Q+/CQBpAQAXAAYJHwgMHQDWAAAMAAYJ8QcHIgCfAAAAAA==.',
Gi='Gilliruni:BAAALgADCgUJBQAAAA==.Gitpull:BAAALgAECggJDgAAAA==.',
Gl='Glazul:BAAALgAECgUJBwAAAA==.Glimley:BAAALgADCgMJAwAAAA==.',
Gn='Gnimsh:BAAALgAECgEJAwAAAA==.Gnorst:BAAALgADCgkJCgAAAA==.',
Go='Goodfoxx:BAAALgAECgEJAQAAAA==.Gorecurse:BAAALgAECgEJAQAAAA==.Goreolio:BAAALgADCgkJDwABLgAECgYJEQABAAAAAA==.',
Gr='Grandmatank:BAAALgADCgkJCQAAAA==.Grasshopaa:BAAALgADCgYJCQAAAA==.Grassy:BAAALgADCgkJCQAAAA==.Greengoatlin:BAAALgADCgcJBwAAAA==.Gremlock:BAAALgAFFAEJAQAAAA==.Gremz:BAABLgAECn8mAAIeAAkJCQrEEABAAQAeAAkJCQrEEABAAQAAAA==.Grozny:BAAALgAECgQJBAABLgAFFAEJAQABAAAAAA==.Grày:BAABLgAECn8wAAINAAkJXx2nIQCBAgANAAkJXx2nIQCBAgAAAA==.',
Gu='Gumboslice:BAACLgAFFH8XAAMEAAcJ9REPDwA1AQAEAAcJ9REPDwA1AQADAAEJLgUSNAAqAAAuAAQKfx8AAgQACQnSHYALAAcDAAQACQnSHYALAAcDAAAA.Gusgus:BAABLgAECn8sAAIGAAkJRwyGDwBvAQAGAAkJRwyGDwBvAQAAAA==.',
['Gä']='Gändälf:BAABLgAECn8XAAIlAAgJvxXFBACgAQAlAAgJvxXFBACgAQAAAA==.',
Ha='Habanero:BAABLgAECn8qAAMPAAkJSA+rPAC8AQAPAAkJSA+rPAC8AQAbAAQJUxhuTgD8AAAAAA==.Hachedev:BAAALgAECgMJCAAAAA==.Hadrîan:BAAALgAECgQJBgAAAA==.Hadtopandadk:BAAALgAECgcJDQAAAA==.Hallia:BAACLgAFFH8GAAIEAAMJ9BHjQACtAAAEAAMJ9BHjQACtAAAuAAQKfzgAAgQACQlTGjcTALECAAQACQlTGjcTALECAAAA.Harika:BAAALgADCgcJBwAAAA==.Hark:BAAALgADCgkJRgAAAA==.Harrybob:BAAALgADCgcJCgAAAA==.Havvocchi:BAAALgAECgEJAwAAAA==.Hawgmane:BAAALgAECgUJBQAAAA==.Hawgwild:BAABLgAECn8mAAINAAkJKxDNYgCiAQANAAkJKxDNYgCiAQAAAA==.',
He='Headdinks:BAAALgADCgcJDAAAAA==.Healcap:BAAALgADCgQJBAAAAA==.Healvisprsly:BAABLgAECn8dAAQEAAkJ3hgWKgAEAgAEAAgJshoWKgAEAgADAAYJ9BgHJgCcAQAkAAMJ3hlwMgDfAAAAAA==.Heisenberg:BAAALgADCgMJAwABLgAECgMJBwABAAAAAA==.Helena:BAABLgAECn9EAAMIAAkJFSSKBgA8AwAIAAkJEySKBgA8AwAJAAkJUB5sBQCbAgAAAA==.Heliarc:BAAALgADCgkJOwAAAA==.Hermès:BAAALgAECgUJBgABLgAFFAgJIgANAFYiAA==.',
Hi='Highfive:BAAALgAECgUJCwAAAA==.Himself:BAAALgAECgEJAQAAAA==.',
Ho='Holeyman:BAAALgADCgcJBwAAAA==.Holybeech:BAAALgAECgQJBAAAAA==.Honestly:BAAALgAFFAIJBAAAAA==.Honkytonkman:BAAALgADCgQJBAAAAA==.Horde:BAAALgAECgEJAQAAAA==.Hover:BAAALgAECgYJEQAAAA==.',
Hu='Huund:BAAALgADCgIJAgAAAA==.',
Ih='Ihmoen:BAAALgADCgYJBgAAAA==.',
Il='Illuminate:BAAALgADCgQJBAAAAA==.Illustria:BAAALgADCgkJLgABLgAECgYJBgABAAAAAA==.Illustriâ:BAAALgADCgkJFgABLgAECgYJBgABAAAAAA==.Illustriä:BAAALgAECgYJBgAAAA==.',
Im='Imprison:BAAALgAECgYJBgABLgAECggJGAAGAJUaAA==.',
In='Infoxxycated:BAAALgAECgEJAQAAAA==.Insidious:BAABLgAECn8fAAIiAAkJFRrLDwAPAgAiAAkJFRrLDwAPAgAAAA==.Invoke:BAAALgADCgEJAQAAAA==.',
Ir='Irs:BAAALgAECgUJBwAAAA==.',
Is='Isisvane:BAAALgAECgkJEQAAAA==.',
It='Itchyfeet:BAAALgAECgUJCAABLgAFFAYJHAAGAFcfAA==.Itchymage:BAACLgAFFH8cAAIGAAYJVx9SOgCBAQAGAAYJVx9SOgCBAQAuAAQKfycAAgYACQnIIzMdAAEDAAYACQnIIzMdAAEDAAAA.Itchyw:BAAALgAFFAEJAQABLgAFFAYJHAAGAFcfAA==.',
Ja='Jacckiemoon:BAAALgAECgQJBAABLgAECgkJHQAEAN4YAA==.Jadehunterr:BAAALgAECgMJBAAAAA==.Jaesn:BAAALgADCgYJBgAAAA==.',
Je='Jeldon:BAAALgADCgQJBAAAAA==.Jenae:BAAALgAECgEJAQAAAA==.Jenövha:BAAALgADCgkJFwAAAA==.Jezebelle:BAAALgAECgUJBQABLgAECgcJDgABAAAAAA==.',
Ji='Jighlipuff:BAAALgAECgIJAgAAAA==.Jigs:BAACLgAFFH8JAAIRAAIJahIeTACNAAARAAIJahIeTACNAAAuAAQKf04AAhEACQlNGkQgAGYCABEACQlNGkQgAGYCAAAA.Jinxy:BAAALgAECgcJDgAAAA==.Jiräiya:BAAALgADCgYJBgAAAA==.',
Jo='Johastrasz:BAAALgADCggJCAAAAA==.',
Ju='Junsing:BAAALgADCgEJAQABLgAFFAIJAgABAAAAAA==.',
['Jå']='Jåfar:BAAALgADCgEJAgAAAA==.',
Ka='Kabøchi:BAAALgAECgUJBQAAAA==.Kafia:BAAALgAECgEJAgAAAA==.Kaladriel:BAAALgADCgEJAQAAAA==.Kaldrick:BAABLgAECn8kAAMbAAkJuRnoGwACAgAbAAkJ8xXoGwACAgAcAAMJWhpbBwDkAAAAAA==.Kamstareater:BAABLgAECn8mAAIgAAkJ+hLbPgDNAQAgAAkJ+hLbPgDNAQAAAA==.Kanakas:BAABLgAECn8UAAIHAAkJohtXHQAYAgAHAAkJohtXHQAYAgAAAA==.Kanaloa:BAABLgAECn8rAAIGAAkJ3AwKeACJAQAGAAkJ3AwKeACJAQAAAA==.Kayler:BAAALgAECgYJBgABLgAECgkJAwABAAAAAA==.',
Ke='Kegerator:BAAALgAECgUJBgAAAA==.Keirin:BAAALgAECggJEgAAAA==.Keldica:BAAALgAECgcJCAABLgAECgkJLAAGACoiAA==.Kelemver:BAAALgADCgMJAwAAAA==.Kelysa:BAAALgAECggJDwAAAA==.Kena:BAAALgADCgUJBQAAAA==.Kenshan:BAAALgAECgQJBAAAAA==.Kevinbox:BAAALgAECgYJEAAAAA==.Kevinslayer:BAAALgAECgUJDAAAAA==.Keynaridan:BAABLgAECn8ZAAIgAAgJ1xJHVACJAQAgAAgJ1xJHVACJAQAAAA==.Keyss:BAAALgADCgIJAgAAAA==.',
Kg='Kglizard:BAAALgAECgUJCAAAAA==.',
Kh='Khalinor:BAABLgAECn8lAAIHAAkJXhcPEgCCAgAHAAkJXhcPEgCCAgAAAA==.Khardun:BAAALgAECgEJAQAAAA==.Khotuhn:BAABLgAECn8UAAIJAAYJbxcVBQBLAQAJAAYJbxcVBQBLAQAAAA==.',
Ki='Kickazdin:BAACLgAFFH8OAAIHAAUJvRf8GABbAQAHAAUJvRf8GABbAQAuAAQKfyIAAwcACQm7HisHABkDAAcACQm7HisHABkDAAgAAgkFCllDAWkAAAAA.Killadragon:BAAALgADCgUJBQAAAA==.Kiryie:BAABLgAECn8bAAIRAAkJDQ8cXgCMAQARAAkJDQ8cXgCMAQAAAA==.Kisäme:BAAALgAECggJDgAAAA==.',
Kl='Klad:BAAALgAECgEJAwAAAA==.Klaw:BAAALgAECgEJAQAAAA==.Kluma:BAAALgAECgEJAQAAAA==.',
Kn='Knok:BAAALgAECggJCAAAAA==.',
Ko='Kobu:BAAALgADCgUJBgAAAA==.Konran:BAAALgADCgEJAQAAAA==.',
Kp='Kprist:BAAALgAECgEJAQAAAA==.',
Kr='Kraigen:BAABLgAECn8wAAIfAAkJLh6WBwC3AgAfAAkJLh6WBwC3AgAAAA==.Krinack:BAABLgAECn8lAAIYAAkJfBLGFgDnAQAYAAkJfBLGFgDnAQAAAA==.Krixiz:BAAALgAECgYJCgAAAA==.',
Ks='Kshamify:BAABLgAFFH8HAAIPAAMJzBMuVwCgAAAPAAMJzBMuVwCgAAAAAA==.',
Ku='Kurindrixx:BAAALgADCgIJAgAAAA==.Kuroi:BAAALgADCgUJBQAAAA==.Kurtakum:BAAALgADCgMJAwAAAA==.Kutiel:BAABLgAECn8ZAAMbAAcJUgrdUAD0AAAbAAcJUgrdUAD0AAAPAAEJtQkcQQAhAAAAAA==.',
Kw='Kwarify:BAAALgADCgEJAQAAAA==.',
Ky='Kynasmira:BAAALgADCgkJJQAAAA==.Kyrsh:BAAALgADCgcJEAAAAA==.',
La='Ladrona:BAABLgAECn8ZAAIFAAkJ+B0lAgDHAgAFAAkJ+B0lAgDHAgAAAA==.Lailyre:BAAALgAECgYJCwABLgAECgkJAwABAAAAAA==.Lassan:BAAALgAECgYJCQAAAA==.Later:BAAALgAECggJDAAAAA==.Latimir:BAAALgAECgIJAgAAAA==.Laur:BAAALgADCgYJBgAAAA==.Lavendeer:BAABLgAECn8qAAIDAAkJNxQBHwDQAQADAAkJNxQBHwDQAQAAAA==.Laydin:BAAALgAECgkJCAABLgAECgkJKAAEAMgDAA==.Laylana:BAAALgAECgEJAQAAAA==.Lazyeye:BAAALgADCgUJBAABLgAECgcJDgABAAAAAA==.',
Lb='Lb:BAAALgADCgUJBgABLgAECgkJFAAbACIZAA==.',
Le='Legume:BAAALgADCgcJCAABLgAECgUJDQABAAAAAA==.Legzanot:BAACLgAFFH8hAAIbAAUJbAs5IACjAAAbAAUJbAs5IACjAAAuAAQKfzQAAhsACQlYF2MIAFEBABsACQlYF2MIAFEBAAAA.Leonceault:BAAALgAECgEJAQAAAA==.Lestrade:BAAALgAECgYJBgAAAA==.',
Li='Lifebringa:BAABLgAECn8sAAMWAAgJTh9pCwCwAgAWAAcJ4yJpCwCwAgAaAAcJxhWmJgCXAQAAAA==.Lightningfox:BAABLgAECn83AAMIAAkJsBp9CQDbAQAIAAkJsBp9CQDbAQAHAAIJug7vdABmAAAAAA==.Lightsfallen:BAAALgAECgkJDwAAAA==.Lileth:BAAALgAECgYJBAAAAA==.Lilylulu:BAAALgADCgIJAgAAAA==.Limzzmagus:BAAALgAECgMJBgAAAA==.Liriel:BAAALgADCgMJAwABLgAECgcJDgABAAAAAA==.Lithia:BAABLgAECn8bAAINAAkJzQ94cgB/AQANAAkJzQ94cgB/AQAAAA==.Littlemo:BAAALgAECgcJEAAAAA==.',
Lo='Loggs:BAAALgAFFAEJAQAAAA==.Lohnar:BAAALgAECgcJEAAAAA==.Lornah:BAAALgADCgQJBAAAAA==.',
Lu='Lucidslock:BAAALgADCgIJAgAAAA==.Lucielbaal:BAABLgAECn8sAAIUAAkJ9R4LDwDUAgAUAAkJ9R4LDwDUAgAAAA==.Luciferus:BAAALgAECgUJCAABLgAFFAMJCwAVAMYFAA==.Luckystop:BAABLgAECn8ZAAMPAAcJhSJXFACpAgAPAAcJhSJXFACpAgAbAAQJNwqOagCoAAAAAA==.Lumenir:BAAALgAECgEJAQAAAA==.Lunareth:BAAALgAECgUJBQABLgAFFAEJAQABAAAAAA==.Luraris:BAAALgAECgEJAQAAAA==.',
Ly='Lyrska:BAABLgAECn8vAAIVAAkJLRETFAAEAgAVAAkJLRETFAAEAgAAAA==.Lyset:BAAALgADCgIJAgAAAA==.Lytearrow:BAABLgAECn8oAAIRAAkJnA8bYQCEAQARAAkJnA8bYQCEAQAAAA==.',
['Lè']='Lèonidas:BAAALgAECgEJAwABLgAECgkJNAAkAEwXAA==.',
['Lé']='Léaf:BAAALgAECgMJAwAAAA==.',
Ma='Madfaith:BAAALgADCgEJAQAAAA==.Mahrylee:BAAALgAECgcJEAAAAA==.Maiya:BAAALgADCgcJEAAAAA==.Majutsu:BAAALgADCgEJAQABLgADCgcJDgABAAAAAA==.Malbrax:BAABLgAECn8ZAAIUAAgJcxIzVACfAQAUAAgJcxIzVACfAQAAAA==.Maleficents:BAABLgAECn8uAAIDAAcJZRN6LgBnAQADAAcJZRN6LgBnAQAAAA==.Malurius:BAABLgAECn8bAAMmAAkJshSzEADoAQAmAAkJsRKzEADoAQACAAYJ4AosZwDBAAAAAA==.Malware:BAAALgAECgYJEQAAAA==.Manana:BAAALgADCgEJAQAAAA==.Manbearpally:BAAALgAECgQJBAAAAA==.Manikfury:BAABLgAECn8iAAMjAAgJwBu6CQAmAgAjAAgJwBu6CQAmAgAEAAYJYx5ZLQDxAQAAAA==.Maniksmage:BAAALgAECggJEgABLgAECggJIgAjAMAbAA==.Mannypack:BAABLgAECn8eAAQDAAgJixwTFQAoAgADAAgJixwTFQAoAgAEAAQJkAz6gQC1AAAkAAEJOxOocAA3AAAAAA==.Maranelli:BAAALgAECgIJAwAAAA==.Maseles:BAAALgAECgUJBgABLgAECgUJCQABAAAAAA==.Mathagni:BAAALgADCgcJBwAAAA==.Maxiticon:BAACLgAFFH8GAAIZAAMJiQjpIACLAAAZAAMJiQjpIACLAAAuAAQKfxgABBoABglNCLxgAJYAABoABQnRBbxgAJYAABYABQmiBdVUAIkAABkAAgmKDVgmADAAAAAA.',
Mc='Mcdawg:BAAALgADCgYJCgAAAA==.Mcleary:BAAALgAECgYJCQAAAA==.',
Me='Meldrus:BAAALgAECgQJBAAAAA==.Melinashala:BAABLgAECn9MAAIUAAkJmQcjDwASAQAUAAkJmQcjDwASAQAAAA==.Mending:BAAALgAECgYJEAAAAA==.Meowinator:BAAALgAECgYJDQAAAA==.Mephizto:BAAALgAECgYJCQAAAA==.Metide:BAAALgAECgQJBAAAAA==.',
Mi='Miala:BAAALgAECgEJAQAAAA==.Mierna:BAAALgAECgkJEgAAAA==.Miler:BAAALgAECggJCgAAAA==.Millylittle:BAAALgADCgUJBQAAAA==.Minisor:BAAALgAECgUJBQAAAA==.Minx:BAAALgADCgIJAQAAAA==.Misanth:BAAALgAECgYJDgAAAA==.Mistdruid:BAAALgAECgIJAwABLgAECgIJBgABAAAAAA==.',
Mo='Moemo:BAABLgAECn8qAAIEAAkJ5CAPCwANAwAEAAkJ5CAPCwANAwAAAA==.Mogryn:BAAALgAECgkJEwAAAA==.Moistymists:BAAALgAECgYJCQAAAA==.Moll:BAAALgADCgEJAQAAAA==.Mommybree:BAAALgAECgYJEgAAAA==.Monksterz:BAABLgAECn8wAAIQAAkJfCEnBgDaAgAQAAkJfCEnBgDaAgAAAA==.Monophobic:BAAALgAECgcJBwAAAA==.Monotonous:BAAALgAECgIJAgAAAA==.Monoxidê:BAAALgAECgEJAQAAAA==.Moonwarriorx:BAAALgAECggJDAAAAA==.Moozle:BAAALgAECgEJAQAAAA==.Morsecode:BAABLgAECn8lAAIMAAkJPRfHCAC+AQAMAAkJPRfHCAC+AQABLgAECgEJAQABAAAAAA==.Morthok:BAABLgAECn8rAAIUAAgJCBhOOwDtAQAUAAgJCBhOOwDtAQAAAA==.Mortischa:BAAALgAECgcJCAAAAA==.Mosh:BAABLgAECn8bAAIQAAkJDhQSGgDVAQAQAAkJDhQSGgDVAQAAAA==.',
Mu='Muchuchu:BAAALgAECgUJEQABLgAECgIJAgABAAAAAA==.Muldern:BAAALgAECgEJAQAAAA==.Munkee:BAAALgAECgYJEQAAAA==.Murdinbronze:BAAALgADCgUJCAAAAA==.Mustachekick:BAAALgAECgUJBQAAAA==.Musyl:BAAALgADCgEJAQABLgAECgYJEQABAAAAAA==.',
['Mã']='Mãf:BAABLgAECn8kAAMPAAgJVxH6VABhAQAPAAgJVxH6VABhAQAbAAEJtxx2kABRAAAAAA==.',
['Mí']='Místwalker:BAAALgAECgIJBgAAAA==.',
Na='Nackthyr:BAACLgAFFH8cAAMKAAUJCiYnAQCyAQAKAAUJCiYnAQCyAQALAAIJNRvOTACbAAAuAAQKfz0AAgoACQmxJkcAAHcDAAoACQmxJkcAAHcDAAAA.Naelyn:BAAALgAECgEJAQAAAA==.Nafir:BAAALgADCgYJFwAAAA==.Nakky:BAAALgAECgYJDgAAAA==.Naritra:BAAALgAECgkJAwAAAA==.Narlin:BAAALgAECgYJCQAAAA==.Nasta:BAABLgAECn8bAAIIAAYJ6Qhc4QDcAAAIAAYJ6Qhc4QDcAAAAAA==.Natureboi:BAAALgADCgQJBAABLgADCgYJDAABAAAAAA==.Nazareths:BAAALgAECgQJCwAAAA==.Nazgor:BAABLgAECn8YAAINAAkJjxc4CwCIAQANAAkJjxc4CwCIAQAAAA==.Nazrien:BAAALgAECgUJBQAAAA==.',
Ne='Neckromancy:BAAALgAECgYJCgAAAA==.Necrosius:BAAALgAECgYJDwAAAA==.Neonarc:BAEALgADCgkJPgAAAA==.Neshi:BAAALgAECgMJBQAAAA==.Neuman:BAAALgADCgEJAQAAAA==.Neval:BAAALgAFFAMJAwABLgAFFAgJHwAVAKQSAA==.',
Ni='Nibblemah:BAAALgAECgcJCwAAAA==.Nightsbane:BAAALgAECgEJAQAAAA==.Nikmonk:BAAALgAECgUJBQABLgAECgkJMwAfAGQfAA==.Nivdk:BAAALgADCgYJBgABLgAECgYJEQABAAAAAA==.Nivora:BAAALgAECgYJEQAAAA==.',
No='Notsure:BAABLgAECn8iAAIOAAkJ4wVfJwD4AAAOAAkJ4wVfJwD4AAAAAA==.',
Nu='Nukacolá:BAAALgADCgYJBgAAAA==.Nutt:BAAALgAECgEJAQAAAA==.',
Ny='Nyxstalia:BAAALgAECgUJDAAAAA==.Nyyx:BAABLgAECn8jAAIgAAgJMwg5nQDnAAAgAAgJMwg5nQDnAAAAAA==.',
['Ná']='Nácl:BAAALgAFFAEJAQABLgAFFAUJHAAKAAomAA==.',
Oa='Oath:BAAALgAECgUJBQAAAA==.',
Ob='Obscyra:BAAALgAFFAEJAQAAAA==.',
Od='Oddyeppal:BAAALgADCgcJBwAAAA==.',
Ol='Olmek:BAACLgAFFH8hAAICAAkJ2RiYBQDxAQACAAkJ2RiYBQDxAQAuAAQKfx8AAgIABwk7JlQPAIACAAIABwk7JlQPAIACAAAA.',
Oo='Oochie:BAAALgADCgQJAwAAAA==.Oochiee:BAAALgADCgEJAQAAAA==.Oonagi:BAAALgAECgUJBQAAAA==.',
Op='Opalana:BAAALgADCgIJAwAAAA==.Ophiana:BAAALgAECgEJBAAAAA==.Oprahwndfury:BAAALgAECgYJEQABLgAECgkJHQAEAN4YAA==.',
Or='Orasaya:BAAALgADCgYJBgAAAA==.Orphee:BAAALgADCgcJBwAAAA==.Orzanis:BAAALgADCgcJDgAAAA==.',
Ow='Owlcapone:BAAALgADCgEJAQAAAA==.',
Oy='Oyveygoyim:BAAALgAFFAMJAwAAAA==.',
Pa='Paige:BAAALgADCgcJDgAAAA==.Palasades:BAAALgADCgUJBQAAAA==.Pallymarc:BAAALgADCgcJCwAAAA==.Pallytune:BAACLgAFFH8RAAIHAAMJPxPYLQDDAAAHAAMJPxPYLQDDAAAuAAQKfxwAAgcACQnxDi0lAN0BAAcACQnxDi0lAN0BAAEuAAUUBAkJAAQAvAYA.Pandalorian:BAAALgAECgYJEgAAAA==.Pandamajack:BAAALgAECggJEwAAAA==.Pandore:BAABLgAECn8UAAIPAAkJcRGqBwDVAQAPAAkJcRGqBwDVAQAAAA==.Paîîy:BAAALgAECgEJAQAAAA==.',
Ph='Philandre:BAABLgAECn8pAAIIAAkJmRRvYgCrAQAIAAkJmRRvYgCrAQAAAA==.',
Pi='Picoso:BAABLgAECn8iAAIGAAkJrw36aQCoAQAGAAkJrw36aQCoAQAAAA==.Piianca:BAAALgAECgUJBgAAAA==.Piianna:BAABLgAECn8aAAIWAAgJHRmcGwDrAQAWAAgJHRmcGwDrAQAAAA==.Pirko:BAAALgADCggJCwAAAA==.',
Po='Pocketheal:BAAALgADCgkJEAAAAA==.Popeweaseliv:BAAALgADCgEJAQABLgAFFAMJBAABAAAAAA==.',
Pr='Probzedgy:BAAALgAECgUJBgAAAA==.',
Pt='Pteradactyl:BAAALgAECgYJBgAAAA==.',
Pu='Punch:BAAALgAECgEJAgAAAA==.Punchingfox:BAAALgAECgEJAQAAAA==.Purgespam:BAAALgAECgcJBwAAAA==.Purplerain:BAAALgAECgUJBgAAAA==.Putrigord:BAAALgAECgQJCwAAAA==.',
Py='Pylarthius:BAAALgADCgcJBwAAAA==.',
['Pø']='Pøwe:BAAALgAECgEJAQABLgAECgkJHQAEAN4YAA==.',
Qa='Qatbarph:BAAALgAECgYJBgAAAA==.',
Qi='Qik:BAAALgAECgEJAQAAAA==.Qikkaw:BAABLgAECn8/AAMPAAkJMxS5CwB4AQAPAAkJMxS5CwB4AQAbAAcJwhFOCQA8AQAAAA==.Qitetsu:BAAALgAECgUJBgAAAA==.',
Qu='Quantos:BAABLgAECn9QAAIkAAkJUxZvAgD/AQAkAAkJUxZvAgD/AQAAAA==.Qulight:BAAALgAECgYJCAABLgAECgkJMQAZACsfAA==.Ququmatz:BAAALgADCgMJAwAAAA==.',
Ra='Raatha:BAABLgAECn8hAAIIAAkJeRY6NAAvAgAIAAkJeRY6NAAvAgAAAA==.Raeyla:BAAALgAECgcJEwAAAA==.Raganar:BAABLgAECn9PAAIJAAkJthWUAgDiAQAJAAkJthWUAgDiAQAAAA==.Ranlerodis:BAAALgADCgMJAwAAAA==.Rasz:BAAALgAECgYJEAAAAA==.Rayjean:BAAALgADCgkJIwAAAA==.Raynik:BAAALgADCgMJAwABLgADCgkJIwABAAAAAA==.',
Re='Redneckboots:BAAALgADCgEJAQAAAA==.Reider:BAAALgAECgQJBAAAAA==.Relmax:BAABLgAECn8gAAIOAAkJjAkFIgAgAQAOAAkJjAkFIgAgAQAAAA==.Rendeminae:BAAALgADCgcJBwAAAA==.Renri:BAABLgAECn8eAAIYAAcJFBZUHwCbAQAYAAcJFBZUHwCbAQAAAA==.Repose:BAAALgAECgIJAwAAAA==.Revick:BAAALgAECgUJCAAAAA==.Revil:BAAALgADCgIJAgAAAA==.',
Rh='Rhaenýs:BAAALgADCgcJDQAAAA==.Rhayla:BAAALgADCgEJAQAAAA==.Rhonwynn:BAABLgAECn9FAAIPAAkJRh9OAgDPAgAPAAkJRh9OAgDPAgAAAA==.',
Ri='Rikershipdwn:BAABLgAECn8ZAAIRAAgJQRRpTgC3AQARAAgJQRRpTgC3AQAAAA==.Rikersline:BAAALgADCgkJCQAAAA==.Rimish:BAABLgAECn8cAAMHAAkJCRU8FgBaAgAHAAkJCRU8FgBaAgAIAAEJNRvlUABMAAAAAA==.Rimrave:BAABLgAECn8qAAQmAAkJnh0IBwCKAgAmAAkJJRwIBwCKAgACAAYJIxscNQDVAQAOAAYJiB0LGgBqAQAAAA==.Ripavicii:BAAALgAECgEJAQAAAA==.Ritobeans:BAAALgADCgkJPQAAAA==.Rivik:BAAALgAFFAEJBAAAAA==.',
Ro='Robbstark:BAAALgAECgYJDAAAAA==.Robertkenway:BAACLgAFFH8LAAIVAAMJxgXmDgCuAAAVAAMJxgXmDgCuAAAuAAQKfzEAAxUACAnZE6EcALgBABUACAnZE6EcALgBABEAAQkAANfUADAAAAAA.Roguebot:BAAALgADCgkJEgAAAA==.Rohdaric:BAABLgAECn8ZAAIVAAYJUxTNFgBdAQAVAAYJUxTNFgBdAQAAAA==.Rokte:BAABLgAECn8bAAIXAAkJ0w+iDACSAQAXAAkJ0w+iDACSAQAAAA==.Rollhots:BAAALgAECgYJBgAAAA==.Roo:BAAALgAECgEJAwAAAA==.Rook:BAABLgAECn8sAAQMAAgJNyN2BAA2AgAUAAgJxCGuFACpAgAMAAcJcyB2BAA2AgAXAAUJrBueAwBIAQABLgAFFAEJAQABAAAAAA==.Rookeh:BAAALgAFFAEJAQAAAA==.Rookhe:BAAALgAECgUJBQAAAA==.Rosekenway:BAABLgAECn9NAAMEAAkJLRriAQCwAgAEAAkJLRriAQCwAgADAAUJ4Qn5aQB5AAABLgAFFAMJCwAVAMYFAA==.',
Rr='Rratt:BAABLgAECn8XAAIYAAYJugZEDgCOAAAYAAYJugZEDgCOAAAAAA==.',
Ru='Rubimoon:BAAALgAECgUJBQAAAA==.Rumí:BAAALgAECggJCAAAAA==.Running:BAAALgAECgIJAgAAAA==.',
['Rî']='Rîkku:BAAALgAECgEJAgAAAA==.',
['Rú']='Rúfus:BAAALgAECgUJBQAAAA==.',
Sa='Saammiee:BAAALgAECgMJBAAAAA==.Sabiha:BAABLgAECn8UAAMRAAYJaA+qZQA2AQARAAYJaA+qZQA2AQAhAAEJwQPplAAlAAAAAA==.Safewaybag:BAAALgADCgQJBAAAAA==.Saintb:BAAALgAECgUJBAAAAA==.Saintotem:BAABLgAECn8mAAIbAAkJ3xGeJgC2AQAbAAkJ3xGeJgC2AQAAAA==.Samartyr:BAAALgAECgYJCQAAAA==.Samison:BAAALgAECgYJBgAAAA==.Sammiiee:BAAALgADCgQJBAABLgAECgMJBAABAAAAAA==.Sandii:BAAALgADCgkJCgAAAA==.Sangwynaris:BAAALgAECgcJEgAAAA==.Sanilien:BAAALgAECgYJDAAAAA==.Saphiiraa:BAABLgAECn8oAAInAAkJZxIfDgDsAQAnAAkJZxIfDgDsAQAAAA==.Sayahealer:BAAALgADCgcJDgAAAA==.',
Sc='Scorpmage:BAABLgAECn8xAAIGAAkJgRpLCQDaAQAGAAkJgRpLCQDaAQAAAA==.Scramms:BAAALgADCgcJDQAAAA==.Scrams:BAABLgAECn8VAAIhAAcJpwxdFgAFAQAhAAcJpwxdFgAFAQAAAA==.',
Se='Sedrick:BAABLgAECn9PAAMHAAkJZSCKAQCjAgAHAAkJZSCKAQCjAgAIAAcJyBW6cgCIAQAAAA==.Sekendipity:BAAALgADCgEJAQABLgAECgcJDgABAAAAAA==.Sekhmett:BAAALgADCgMJAwAAAA==.Sekndestroy:BAAALgADCgYJCQABLgAECgcJDgABAAAAAA==.Sektacular:BAAALgADCgQJBAABLgAECgcJDgABAAAAAA==.Sekzen:BAAALgAECgcJDgAAAA==.Semiazas:BAABLgAECn8/AAQXAAkJtQ8lAgCyAQAXAAkJtQ8lAgCyAQAUAAUJ2QmotwDpAAAMAAEJAAD7egAnAAAAAA==.Semiazes:BAAALgADCgYJBgAAAA==.Senessa:BAAALgADCgIJAgAAAA==.Sensy:BAAALgAECgQJCQAAAA==.Sepulveda:BAAALgAECgUJBQABLgAECgkJKgAEAOQgAA==.Serwonton:BAAALgADCgUJBQAAAA==.Seumas:BAAALgADCgMJAwAAAA==.',
Sh='Shadrock:BAAALgADCgYJBgAAAA==.Shaio:BAAALgAECgUJBQAAAA==.Shamtune:BAAALgAFFAMJBAABLgAFFAQJCQAEALwGAA==.Sharayman:BAAALgADCgkJFwABLgADCgkJIwABAAAAAA==.Shattered:BAABLgAECn8hAAIeAAkJTxv2AABiAgAeAAkJTxv2AABiAgAAAA==.Shayrisa:BAABLgAECn9JAAMbAAkJAhVgBADiAQAbAAkJAhVgBADiAQAPAAkJTBLLDgBAAQAAAA==.Shazool:BAABLgAECn8cAAMPAAkJlB7rEgC1AgAPAAkJlB7rEgC1AgAcAAIJkQtPMgBoAAABLgAFFAMJBgAEAPQRAA==.Sheep:BAABLgAECn8YAAMGAAgJlRpsSwD5AQAGAAgJshlsSwD5AQAlAAIJmBkAFABMAAAAAA==.Shifterz:BAAALgAECgcJDwAAAA==.Shrieke:BAAALgAECgYJCQAAAA==.Shrubbery:BAABLgAECn8gAAIkAAkJvBAmHABtAQAkAAkJvBAmHABtAQAAAA==.Shxdow:BAAALgAECgQJBAAAAA==.',
Si='Sind:BAABLgAECn8bAAIJAAgJRhaZDwDKAQAJAAgJRhaZDwDKAQABLgAECgkJNAAkAEwXAA==.Sindella:BAAALgAECgYJEwABLgAECgkJNAAkAEwXAA==.Sindrè:BAAALgAECgYJBwABLgAECgkJNAAkAEwXAA==.Sinistèr:BAAALgAECgMJAwABLgAECgkJNAAkAEwXAA==.Sinna:BAAALgADCgUJCQABLgAECgEJAQABAAAAAA==.Sinthorne:BAABLgAECn80AAMkAAkJTBdTBQBkAQAkAAkJTBdTBQBkAQAjAAMJ8AW9PQBjAAAAAA==.',
Sk='Skedaddle:BAAALgAECgYJCwABLgAECgkJPwAGAEYkAA==.Skithíryx:BAAALgAECgcJDwAAAA==.Skoodal:BAAALgADCgIJAgAAAA==.Skylight:BAAALgAECgEJAQAAAA==.',
Sl='Slashbndcoot:BAAALgAFFAMJAwAAAA==.Slashgquit:BAACLgAFFH8SAAIiAAQJniDZEwBSAQAiAAQJniDZEwBSAQAuAAQKfzUAAiIACQmIJOYDAPwCACIACQmIJOYDAPwCAAAA.Slinx:BAAALgADCgMJAwAAAA==.Slumbermist:BAABLgAECn8+AAMTAAkJxhEzHgC8AQATAAkJxhEzHgC8AQAdAAcJgxJODgA/AQABLgAECgEJAQABAAAAAA==.',
So='Solaire:BAABLgAECn8hAAMJAAcJWRzfEAC2AQAJAAcJWRzfEAC2AQAHAAUJqRDSTwD6AAABLgAFFAQJCQATAMQiAA==.Soras:BAAALgADCgkJHwAAAA==.Sorq:BAAALgAECgUJBQAAAA==.Sourjack:BAAALgAECgUJBgAAAA==.',
St='Steph:BAAALgAFFAIJAgAAAA==.',
Su='Sunareas:BAAALgADCgIJAgAAAA==.',
Sy='Syndar:BAAALgAECgQJBAABLgAECgkJLAAGACoiAA==.Synthetic:BAABLgAECn8nAAIMAAkJWxYHCADPAQAMAAkJWxYHCADPAQAAAA==.Syrebriel:BAAALgADCgEJAgABLgAECgcJGQAbAFIKAA==.',
Sz='Szasstaam:BAABLgAECn8kAAMlAAkJ4wc+BwA9AQAlAAkJ4wc+BwA9AQAGAAQJGQIAJwFsAAAAAA==.',
['Sé']='Sénåtor:BAAALgADCgYJCAABLgAECgkJLwAIAHgUAA==.Séékér:BAAALgADCgcJFQAAAA==.',
Ta='Talanith:BAAALgADCggJEAAAAA==.Tarayk:BAAALgADCgYJCAABLgADCgkJIwABAAAAAA==.Tarnadal:BAAALgAECgEJAQAAAA==.Taxal:BAAALgADCgYJBwAAAA==.Taxlock:BAABLgAECn8aAAIUAAcJ9wmGmwAGAQAUAAcJ9wmGmwAGAQAAAA==.',
Tb='Tbagjones:BAAALgAECgQJBAAAAA==.',
Te='Tecsaran:BAABLgAECn8sAAIGAAkJKiJaAgAbAwAGAAkJKiJaAgAbAwAAAA==.Tekis:BAAALgAECgUJBgAAAA==.Telz:BAAALgAECgYJCgAAAA==.Terania:BAAALgADCgIJAgAAAA==.',
Th='Thalira:BAABLgAECn8eAAQnAAkJYwfpGwAgAQAnAAkJYwfpGwAgAQALAAcJTwIocACLAAAKAAQJrQGENQBpAAAAAA==.Thetowelie:BAAALgAECgEJAQAAAA==.',
Ti='Tibbz:BAAALgADCgIJAgAAAA==.Tiger:BAACLgAFFH8+AAQjAAkJECUBAACwAwAjAAkJECUBAACwAwAkAAQJiCLVDAArAQAEAAMJYhpwMwDgAAAuAAQKfyoAAyMACQnqJgUAABYEACMACQnqJgUAABYEAAQAAQm1C4TEAD8AAAAA.Tinkera:BAAALgAECgQJBAAAAA==.Tinnea:BAAALgAECgUJDgAAAA==.Titanosaurus:BAAALgAECgcJEAAAAA==.Tizzly:BAABLgAECn8rAAIGAAkJzQ5vagCnAQAGAAkJzQ5vagCnAQAAAA==.',
To='Torhilda:BAAALgAECgYJBgABLgAECgkJLAAGACoiAA==.Torridwells:BAABLgAECn8bAAIRAAkJdQ/RWgCVAQARAAkJdQ/RWgCVAQAAAA==.',
Tr='Trad:BAAALgADCgYJBgAAAA==.Troag:BAABLgAECn8fAAIPAAkJdxz1GgBzAgAPAAkJdxz1GgBzAgAAAA==.Troagstar:BAABLgAECn8nAAIbAAkJ/BrlGwACAgAbAAkJ/BrlGwACAgAAAA==.',
Ts='Tsaesci:BAAALgADCgQJBgAAAA==.Tsynn:BAAALgADCgYJFAAAAA==.',
Tw='Tweetymae:BAAALgAECgEJAQAAAA==.',
Ty='Tylerz:BAAALgAFFAEJAQAAAA==.Tyraana:BAACLgAFFH8RAAIfAAQJtBoMBwBTAQAfAAQJtBoMBwBTAQAuAAQKf0UAAx8ACQkpIZEFAOcCAB8ACQkpIZEFAOcCACAACAndFGVMAKABAAAA.Tyrinwar:BAAALgADCgYJDAAAAA==.Tyrmog:BAABLgAECn8fAAINAAkJVQl/lgA7AQANAAkJVQl/lgA7AQAAAA==.Tytus:BAAALgAECgUJBQAAAA==.',
Un='Unique:BAAALgAECgEJAQABLgAFFAYJGwACADkkAA==.',
Us='Ushas:BAABLgAECn8yAAMWAAkJChmrGQD+AQAWAAkJChmrGQD+AQAZAAQJqQXgWwCQAAAAAA==.Usmcdawg:BAAALgADCgcJBwAAAA==.Usmcshammy:BAABLgAECn8UAAMPAAYJNgp6GADNAAAPAAYJNgp6GADNAAAbAAMJ3gL8JgBCAAAAAA==.',
Va='Vali:BAABLgAECn8sAAIhAAkJHB/vAgCyAgAhAAkJHB/vAgCyAgAAAA==.Valindrea:BAAALgAECgcJEAAAAA==.Vandressa:BAAALgADCgMJAwAAAA==.Vasrael:BAABLgAECn82AAMIAAkJshd3OwAWAgAIAAgJ/Bl3OwAWAgAHAAcJYRzcHQAUAgAAAA==.Vav:BAABLgAECn8UAAMRAAYJeBdqoQD/AAARAAYJeBdqoQD/AAAVAAIJswzTYAA5AAAAAA==.',
Ve='Vecnis:BAAALgAECgIJAgAAAA==.Veliette:BAAALgAECgUJCwAAAA==.Verdena:BAAALgADCgcJBwABLgADCgkJIwABAAAAAA==.Vexen:BAABLgAECn8mAAMgAAkJPRQ0BQDcAQAgAAkJIRQ0BQDcAQAfAAIJyhYBEgCLAAAAAA==.',
Vi='Victaliste:BAAALgAECgQJBQAAAA==.Vithper:BAAALgAECggJEwAAAA==.',
Vn='Vnia:BAAALgAECgEJAQABLgAECgMJCAABAAAAAA==.',
Vo='Voidmuffinz:BAACLgAFFH8IAAIgAAMJ4gz0agC2AAAgAAMJ4gz0agC2AAAuAAQKfyMAAiAACQkmGE4tABICACAACQkmGE4tABICAAAA.',
Vy='Vynis:BAAALgAECgcJDQABLgAFFAQJCQAEALwGAA==.Vyrahildard:BAABLgAECn8uAAIIAAkJfRuWJwBlAgAIAAkJfRuWJwBlAgAAAA==.',
Wa='Wakkiq:BAAALgAECgEJAQAAAA==.Waringoutlaw:BAABLgAECn8UAAICAAcJYgGangA3AAACAAcJYgGangA3AAAAAA==.Wasteland:BAABLgAECn8rAAIiAAkJphEvGwCDAQAiAAkJphEvGwCDAQAAAA==.',
We='Weaselhunter:BAAALgAFFAIJAwABLgAFFAMJBAABAAAAAA==.Weasellock:BAACLgAFFH8HAAIUAAIJ8BYikgCeAAAUAAIJ8BYikgCeAAAuAAQKfxEAAhQABgm+GLR8AD8BABQABgm+GLR8AD8BAAEuAAUUAwkEAAEAAAAA.Weaselmage:BAAALgAFFAMJBAAAAA==.Welor:BAAALgADCgYJDAAAAA==.',
Wh='Whatthef:BAAALgAECggJCwAAAA==.',
Wi='Wikkaq:BAAALgAECgEJBAAAAA==.Wildweasel:BAABLgAFFH8FAAIIAAIJgBqXRQCPAAAIAAIJgBqXRQCPAAABLgAFFAMJBAABAAAAAA==.Willbar:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.Willbarr:BAAALgAECgEJAQAAAA==.Winterhide:BAABLgAECn8xAAINAAkJoxnBIwB2AgANAAkJoxnBIwB2AgAAAA==.',
Wo='Wolfe:BAAALgADCgIJAgAAAA==.',
Xa='Xallie:BAECLgAFFH8GAAIgAAMJaQgQcACpAAAgAAMJaQgQcACpAAAuAAQKf0AAAiAACQl8GoUgAFECACAACQl8GoUgAFECAAAA.Xanvyr:BAABLgAECn8hAAIIAAkJXxk8PwAJAgAIAAkJXxk8PwAJAgAAAA==.Xaquillis:BAACLgAFFH8VAAMSAAUJlQyECgDzAAASAAQJaguECgDzAAANAAQJuQ0ytQC8AAAuAAQKfyYAAw0ACQkuGyc8AEcCAA0ACAmZGyc8AEcCABIABAmwFr0VACsBAAAA.Xarthis:BAAALgAECgEJAQABLgAFFAUJFQASAJUMAA==.',
Xe='Xentrie:BAAALgADCgUJCgAAAA==.Xeyvara:BAABLgAECn8tAAIeAAkJoCTaAABCAwAeAAkJoCTaAABCAwAAAA==.',
Xg='Xg:BAAALgADCgUJBgABLgAECgYJJgAbALwfAA==.',
Xi='Xindra:BAAALgAECgkJCQAAAA==.',
Ya='Yah:BAAALgADCgUJBQAAAA==.Yamiyugi:BAAALgAECgEJAQAAAA==.Yatsui:BAAALgAECgQJBAAAAA==.',
Yo='Youngthug:BAAALgAECgIJAwAAAA==.',
Yu='Yutaa:BAAALgADCgYJBgAAAA==.',
Za='Zaden:BAAALgAECgYJCQAAAA==.Zangi:BAAALgAECgEJAwABLgAECgkJLAAEAL4hAA==.Zarihanna:BAABLgAECn9AAAIGAAgJax3rBQBJAgAGAAgJax3rBQBJAgAAAA==.Zatannah:BAAALgADCgUJBQAAAA==.',
Ze='Zedryn:BAABLgAECn8nAAIUAAkJew92RwDDAQAUAAkJew92RwDDAQAAAA==.Zenshi:BAAALgAECgEJAgAAAA==.Zeperios:BAAALgAECgYJCgAAAA==.Zeril:BAABLgAECn8UAAMXAAgJjReLDACTAQAXAAgJjReLDACTAQAUAAEJHgXrVwEoAAAAAA==.Zerq:BAAALgADCgkJEAAAAA==.Zestdruid:BAAALgAECggJEQAAAA==.Zestull:BAABLgAECn8lAAIQAAgJnCS2BgDOAgAQAAgJnCS2BgDOAgAAAA==.Zetsuboiki:BAAALgADCgcJCwAAAA==.Zetsudeath:BAAALgADCgYJBgAAAA==.Zetsudemon:BAAALgADCgMJAwAAAA==.',
Zh='Zhoel:BAAALgADCgEJAQAAAA==.',
Zi='Ziak:BAAALgAECgUJBQAAAA==.Zindeshal:BAAALgAECgYJCQAAAA==.',
Zo='Zorc:BAACLgAFFH8WAAIbAAUJhBcqGwBBAQAbAAUJhBcqGwBBAQAuAAQKfycAAhsACQmKIPsJAPQCABsACQmKIPsJAPQCAAAA.',
Zu='Zunji:BAAALgAECgEJBAAAAA==.',
Zy='Zyate:BAABLgAECn8xAAIUAAkJTRJdRwDEAQAUAAkJTRJdRwDEAQAAAA==.Zyrryn:BAABLgAECn8XAAIKAAgJwQOXEgDhAAAKAAgJwQOXEgDhAAAAAA==.',
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
