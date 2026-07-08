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

local lookup = {'Unknown-Unknown','Warrior-Fury','Druid-Balance','Druid-Restoration','Mage-Frost','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Evoker-Devastation','Evoker-Augmentation','Warlock-Destruction','DeathKnight-Unholy','Warrior-Protection','Shaman-Restoration','Monk-Brewmaster','Hunter-BeastMastery','DeathKnight-Frost','Monk-Windwalker','Warlock-Demonology','Hunter-Survival','Priest-Holy','Warlock-Affliction','Rogue-Subtlety','Priest-Discipline','Shaman-Elemental','Shaman-Enhancement','Monk-Mistweaver','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Marksmanship','DeathKnight-Blood','Druid-Feral','Druid-Guardian','Priest-Shadow','Mage-Arcane','Rogue-Assassination','Warrior-Arms','Evoker-Preservation',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aaffoxx:BAAALgAECgEJAQAAAA==.Aagonyy:BAAALgAECgEJBAAAAA==.',
Ae='Aenninicus:BAAALgAECgEJAgAAAA==.Aernoth:BAAALgAECgUJDQAAAA==.',
Af='Affox:BAAALgAECgEJAQAAAA==.',
Ak='Akaidia:BAAALgAECgYJBgABLgAECgYJCwABAAAAAA==.',
Al='Alderan:BAABLgAECn8lAAICAAcJIg4dQwA5AQACAAcJIg4dQwA5AQAAAA==.Aleinas:BAABLgAECn8kAAMDAAcJKxbLMwBKAQADAAcJKxbLMwBKAQAEAAQJQQixlQCIAAAAAA==.Alektophobia:BAAALgAFFAEJAQAAAA==.Alendra:BAAALgAECgEJAQABLgAECgYJFAAFANQfAA==.Alluisice:BAAALgAECgYJBgAAAA==.Allysaun:BAAALgAECgUJBgAAAA==.Alpharoach:BAAALgADCgYJBgAAAA==.Alufina:BAAALgAECgYJBgABLgAECgkJHAAGAAkVAA==.Alzeinrich:BAABLgAECn8YAAMHAAcJSQd93gDgAAAHAAcJmgV93gDgAAAIAAQJbwjJNwCAAAAAAA==.',
Am='Amorina:BAABLgAECn8cAAIHAAgJzxWpVQDKAQAHAAgJzxWpVQDKAQAAAA==.',
An='Anarii:BAAALgAECgIJAgAAAA==.Anda:BAAALgAECgMJAwAAAA==.Andarnn:BAAALgAECgEJAQAAAA==.Andracca:BAABLgAECn8eAAMJAAkJFAspDABOAQAJAAkJFAspDABOAQAKAAEJQAXynAAkAAAAAA==.Andromeda:BAABLgAECn8XAAIEAAkJWwzzTwBPAQAEAAkJWwzzTwBPAQAAAA==.Aner:BAAALgAECgEJBwAAAA==.Angrygnome:BAACLgAFFH8JAAILAAMJex44CAAUAQALAAMJex44CAAUAQAuAAQKfx4AAgsACQmqILoBAL4CAAsACQmqILoBAL4CAAAA.Angélique:BAAALgAFFAIJAwABLgAFFAcJGgAMAJMiAA==.Antcension:BAAALgADCgUJBQAAAA==.Antemental:BAAALgAECgYJEAAAAA==.Anthigos:BAAALgAECgMJAwAAAA==.',
Ar='Arax:BAABLgAECn8dAAINAAcJ7yHTDgD9AQANAAcJ7yHTDgD9AQAAAA==.Arcada:BAAALgAECgUJBQABLgAECgUJBQABAAAAAA==.Arcaidious:BAAALgAECgUJCgABLgAECggJJAAOAFcRAA==.Arcamoon:BAAALgAECgIJAgABLgAECgUJBQABAAAAAA==.Arcashi:BAAALgADCgcJCgABLgAECgUJBQABAAAAAA==.Arcxdd:BAAALgAECgQJBAAAAA==.Areuawizard:BAAALgAECgYJBgAAAA==.Arianlion:BAAALgAECgQJBQAAAA==.Ariantheone:BAAALgAECgEJAQAAAA==.Armistice:BAAALgAECgEJAgAAAA==.Arowenn:BAAALgADCgMJAwAAAA==.Arrokoth:BAAALgAECgUJCAAAAA==.Artana:BAAALgAECgIJAgAAAA==.Artistic:BAAALgAECgUJBQAAAA==.',
As='Askook:BAAALgAECgkJEwAAAA==.Astolvik:BAAALgAECgQJBgAAAA==.',
At='Attachedplag:BAAALgAFFAEJAQAAAA==.Atulwa:BAABLgAECn8rAAIOAAkJ6xfbIwA3AgAOAAkJ6xfbIwA3AgAAAA==.',
Au='Aurinox:BAABLgAECn8dAAIFAAYJ9w4HugATAQAFAAYJ9w4HugATAQAAAA==.Autodrive:BAABLgAECn8eAAIPAAkJXhyaAACMAgAPAAkJXhyaAACMAgAAAA==.',
Av='Avralea:BAABLgAECn9OAAIPAAgJJBzOEgAdAgAPAAgJJBzOEgAdAgAAAA==.',
Az='Azenthal:BAAALgAECgEJAQAAAA==.Azurestrider:BAAALgAECgEJAQAAAA==.',
['Aç']='Açhilles:BAAALgAECgYJCAABLgAECgkJHQAEAMYYAA==.',
Ba='Baconinja:BAAALgAECgEJAQAAAA==.Bananahammik:BAAALgAECgYJDgAAAA==.Banzen:BAABLgAECn8eAAIQAAUJ/g9LHACWAAAQAAUJ/g9LHACWAAAAAA==.Basz:BAACLgAFFH8OAAIMAAQJKQ9ANQDMAAAMAAQJKQ9ANQDMAAAuAAQKf0YAAwwACQm6HEgFAKcBAAwACAn4HUgFAKcBABEABwlvFXYCACEBAAAA.Battle:BAEALgAECgEJAQABLgAFFAIJBgASAL4hAA==.',
Be='Beefburglar:BAAALgAECgYJBgAAAA==.Beginagain:BAAALgADCgcJCQAAAA==.Belfias:BAAALgAECgEJAgABLgAECgkJFwARAKsaAA==.Belgran:BAABLgAECn8XAAIRAAkJqxrSAwA9AgARAAkJqxrSAwA9AgAAAA==.Belmonte:BAAALgADCgEJAQAAAA==.Belris:BAAALgAECgMJAwAAAA==.Berunma:BAABLgAECn8ZAAIQAAgJ2BBveABPAQAQAAgJ2BBveABPAQAAAA==.Betabill:BAAALgAECgUJBQAAAA==.',
Bh='Bhain:BAABLgAECn8hAAMTAAcJ5R3lSgDpAQATAAcJ5R3lSgDpAQALAAEJaA2FdAAwAAABLgAFFAUJFgAHAKwfAA==.',
Bi='Bileshots:BAABLgAECn8UAAIUAAgJNRciHAC8AQAUAAgJNRciHAC8AQAAAA==.Biowolf:BAACLgAFFH8nAAIFAAUJgglkJQD0AAAFAAUJgglkJQD0AAAuAAQKfywAAgUACQneFBVEAA8CAAUACQneFBVEAA8CAAAA.Birdhunter:BAAALgAFFAEJAQAAAA==.Bishopixixix:BAAALgAECgYJCwABLgAECgcJDwABAAAAAA==.Bits:BAABLgAECn8rAAITAAkJWgfecwBSAQATAAkJWgfecwBSAQAAAA==.',
Bj='Bjoren:BAABLgAECn8wAAIVAAkJGyRSAwBcAwAVAAkJGyRSAwBcAwAAAA==.',
Bl='Blackdread:BAAALgADCgYJBgAAAA==.Blasterjenny:BAAALgAECgQJBQAAAA==.Bloodcaptain:BAABLgAECn8cAAMLAAkJORfuBgDtAQALAAkJZBbuBgDtAQAWAAYJshf6CAC3AQAAAA==.',
Bo='Bohma:BAAALgADCgEJAQAAAA==.Boopblast:BAAALgAECgQJCAAAAA==.Bootiebang:BAABLgAECn8XAAIXAAcJbQSoOgDjAAAXAAcJbQSoOgDjAAAAAA==.Bootieknight:BAAALgAECgUJCAAAAA==.Bootycaall:BAAALgADCgkJGwAAAA==.Bootycall:BAAALgAECgUJCgAAAA==.Boroth:BAAALgADCgcJBwAAAA==.',
Br='Breetech:BAAALgAECgIJAgAAAA==.Brett:BAAALgAECgEJAQAAAA==.Breé:BAAALgAECgEJAQAAAA==.Brianx:BAAALgADCgIJAgAAAA==.Brklyn:BAAALgAFFAEJAQAAAA==.Brockshot:BAAALgADCgcJBwAAAA==.Brokki:BAAALgADCgEJAQAAAA==.',
Bu='Buckaroo:BAAALgAECgQJBQAAAA==.Bucknastey:BAAALgAECgIJAgAAAA==.Bucknekkid:BAABLgAECn8UAAIHAAkJqQWyyAD9AAAHAAkJqQWyyAD9AAAAAA==.Buckwhild:BAABLgAECn8jAAMVAAgJxiEzCQDWAgAVAAgJ4CAzCQDWAgAYAAMJfB3MBgAKAQAAAA==.Burrhus:BAAALgAECgQJBAAAAA==.',
Ca='Cagomei:BAAALgADCggJDgAAAA==.Caladbolg:BAABLgAECn9LAAMIAAgJ2CJyAAChAgAIAAgJ2CJyAAChAgAHAAEJkAP5VwEnAAAAAA==.Camrillem:BAAALgAFFAEJAQAAAA==.Cannacola:BAABLgAECn8mAAMZAAYJvB/KKwCXAQAaAAYJ1BzoDQDeAQAZAAYJOh7KKwCXAQAAAA==.Carebearr:BAAALgAECgMJAwAAAA==.',
Ce='Cearius:BAAALgAECgYJCgABLgAFFAYJFQATAEweAA==.Celthis:BAAALgADCgcJBwABLgAECgUJCQABAAAAAA==.Cerdwin:BAAALgAECgEJAQABLgAECgYJFAAFANQfAA==.Cesàrè:BAABLgAECn8fAAIbAAkJjwmyDQDVAAAbAAkJjwmyDQDVAAAAAA==.',
Ch='Chahra:BAABLgAECn8bAAIcAAkJyw1aEABHAQAcAAkJyw1aEABHAQAAAA==.Chammie:BAAALgAECgYJBgAAAA==.Chamuki:BAACLgAFFH8GAAMdAAMJ4g8/IgCJAAAdAAIJZhY/IgCJAAAeAAEJ2wKkpwAyAAAuAAQKfyYABB0ACAn4HO8OADcCAB0ABwnBIO8OADcCAB4ABQm2DcK5ALgAABwAAgkgGMUGAEYAAAEuAAUUBgkbAAMAMB8A.Chaosbolt:BAAALgAECgEJBwAAAA==.Cheesecake:BAACLgAFFH8aAAMMAAcJkyLrKADGAQAMAAcJkyLrKADGAQARAAIJ3A9CHgCSAAAuAAQKfycAAwwACQl+JcQCAK4DAAwACQl+JcQCAK4DABEAAwn6GuEmAJwAAAAA.Cheesecaké:BAAALgAFFAIJAgABLgAFFAcJGgAMAJMiAA==.Cheesuspiece:BAAALgADCgIJAgAAAA==.Chrispbacon:BAAALgAECgMJBAAAAA==.Chuubak:BAAALgAECgkJBwAAAA==.',
Cl='Clangeddin:BAAALgAECgQJBAAAAA==.Clangedin:BAABLgAECn8uAAICAAkJxwkrBwAAAQACAAkJxwkrBwAAAQAAAA==.',
Co='Cobalt:BAAALgADCgUJBQABLgAFFAMJCgATADYbAA==.Colonidus:BAAALgADCgUJBgAAAA==.Coondic:BAAALgADCgEJAQAAAA==.Coreydruid:BAAALgAECgMJBwAAAA==.Coreypala:BAAALgAECgIJBAAAAA==.Coreysham:BAAALgAECgQJBQAAAA==.Corily:BAAALgADCgcJHAAAAA==.Corsten:BAABLgAECn8sAAINAAgJbhEvAgBsAQANAAgJbhEvAgBsAQAAAA==.Cosmictonic:BAAALgADCgYJBgAAAA==.',
Cr='Crabpack:BAAALgADCgIJAgAAAA==.Crayoneater:BAAALgAECgQJBAAAAA==.Crippleswagg:BAAALgAECgYJAQAAAA==.Croisades:BAAALgAECgQJCgAAAA==.Crosis:BAAALgADCgcJFwAAAA==.Crowmatic:BAABLgAECn8aAAIMAAkJ+h5fJwBlAgAMAAkJ+h5fJwBlAgAAAA==.Crusadan:BAAALgADCgYJBgAAAA==.Cryo:BAAALgAECgEJAQAAAA==.',
Cu='Cucklizard:BAAALgAECgEJAQAAAA==.Cute:BAABLgAFFH8NAAICAAMJNCOSKAATAQACAAMJNCOSKAATAQAAAA==.',
['Cà']='Càhos:BAAALgADCgUJBQAAAA==.',
Da='Dakon:BAABLgAECn83AAMIAAkJThoNCgArAgAIAAkJThoNCgArAgAHAAIJcBi7DAF9AAAAAA==.Dalune:BAABLgAECn8+AAIZAAkJOg36AwBfAQAZAAkJOg36AwBfAQAAAA==.Daneaus:BAABLgAECn8sAAIEAAkJviH0BQBZAwAEAAkJviH0BQBZAwAAAA==.Daniellson:BAACLgAFFH8HAAIUAAMJ1g1YIQDOAAAUAAMJ1g1YIQDOAAAuAAQKfxgABB8ACAkoEesvALUBAB8ACAkoEesvALUBABQAAQk+EKFhADgAABAAAQkAAFrcABcAAAEuAAUUBgkUACAAcRoA.Daredevil:BAAALgAECgYJCQABLgAECggJFwAMALYcAA==.Dargonath:BAAALgAFFAEJAwAAAA==.Darkchronos:BAAALgAECgEJAgAAAA==.Darkehawke:BAAALgAECgEJAQAAAA==.Darkscorp:BAAALgADCgkJEAAAAA==.Darkwolf:BAACLgAFFH8IAAIMAAQJkQbxhwD6AAAMAAQJkQbxhwD6AAAuAAQKfzsAAwwACQm2FC83ACICAAwACQm2FC83ACICACAACAk3BykyANQAAAAA.Darnuus:BAAALgAFFAEJAQAAAA==.Datromandude:BAAALgAECgUJCAAAAA==.Dawnbringer:BAAALgADCgQJBAAAAA==.',
Db='Dblaster:BAAALgAECgUJCwAAAA==.',
De='Deathbydruid:BAABLgAECn8oAAMEAAkJyANFfwC8AAAEAAkJyANFfwC8AAADAAYJ1QCEfwBJAAAAAA==.Deathnelf:BAABLgAECn8bAAQRAAkJ7AnKFgAiAQARAAgJAgvKFgAiAQAMAAYJYQXU8gC9AAAgAAIJQwOIDQBAAAAAAA==.Deazraelle:BAABLgAECn8cAAITAAgJnBvyPADoAQATAAgJnBvyPADoAQAAAA==.Decimator:BAAALgADCggJHwAAAA==.Declan:BAAALgADCgUJBQAAAA==.Dedric:BAABLgAECn8nAAQhAAgJ8wqDIwDuAAAhAAgJGwiDIwDuAAADAAgJKgRJTgDTAAAiAAEJNRcqbAA+AAAAAA==.Deesis:BAAALgADCgEJAQAAAA==.Dellin:BAABLgAECn8qAAIDAAkJFBcgGAAMAgADAAkJFBcgGAAMAgAAAA==.Demeco:BAEBLgAFFH8LAAMHAAcJVxJaCgByAQAHAAYJGxRaCgByAQAGAAQJXw1DCgABAQABLgAFFAkJJgAGAGQcAA==.Demonch:BAAALgAECgUJCAAAAA==.Demonweasel:BAAALgAFFAEJAgABLgAFFAIJBwATAPAWAA==.Depeche:BAABLgAECn8fAAIeAAcJGBK+mgDrAAAeAAcJGBK+mgDrAAAAAA==.Deralle:BAABLgAECn8sAAIKAAkJSQzMOQBFAQAKAAkJSQzMOQBFAQABLgAFFAEJAQABAAAAAA==.Dethrift:BAAALgAECgEJAQAAAA==.',
Di='Dil:BAAALgAECgIJAwABLgAECggJGAAFAJUaAA==.Diminuendo:BAAALgAECgcJEAAAAA==.',
Do='Donalda:BAAALgAECgEJAQAAAA==.Dorillion:BAAALgAECgUJCQAAAA==.Dorozh:BAABLgAECn8gAAILAAgJKhXvCQCnAQALAAgJKhXvCQCnAQAAAA==.',
Dr='Draconx:BAAALgADCgYJBgAAAA==.Draghr:BAAALgAECgQJBAAAAA==.Dragonzmage:BAAALgAECgMJAwAAAA==.Dragskar:BAAALgADCgUJBQAAAA==.Drala:BAABLgAECn8hAAMYAAkJZhPoFwAVAgAYAAkJZhPoFwAVAgAVAAEJ2w77ggAuAAAAAA==.Dreadmage:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.Dreadpally:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Dreadsham:BAAALgADCgIJAgABLgAECgEJAQABAAAAAA==.Dreco:BAAALgADCgcJBwAAAA==.Driver:BAEBLgAFFH8FAAIHAAIJSR2RgQCyAAAHAAIJSR2RgQCyAAABLgAFFAUJEQAWALYLAA==.Dryconias:BAACLgAFFH8OAAIHAAMJvBbgJQDAAAAHAAMJvBbgJQDAAAAuAAQKfzcAAwcACQkmHaYhAIACAAcACQkmHaYhAIACAAgAAQmfCNBUACcAAAAA.Drèadpriest:BAABLgAECn8VAAQYAAUJwR2JJQCjAQAYAAUJux2JJQCjAQAVAAUJ0hR9QgDhAAAjAAIJCRMGUQCJAAAAAA==.Drôgô:BAABLgAECn8VAAIQAAYJnhM7TgB+AQAQAAYJnhM7TgB+AQABLgAECggJCAABAAAAAA==.',
Du='Dunkelzhan:BAABLgAECn9iAAIFAAkJdB/VAQDRAgAFAAkJdB/VAQDRAgAAAA==.Duntack:BAAALgADCgEJBAAAAA==.',
Dy='Dyana:BAABLgAECn8gAAIQAAgJ2BVJRgDPAQAQAAgJ2BVJRgDPAQAAAA==.',
Dz='Dz:BAACLgAFFH8MAAMGAAQJhRkuIAAcAQAGAAQJhRkuIAAcAQAHAAQJPwmwVgACAQAuAAQKf0UAAwYACQlBJlsAAN8DAAYACQlBJlsAAN8DAAcABQlHD6b4AMAAAAAA.',
['Dø']='Dømimømmÿ:BAAALgAECgUJCAAAAA==.',
Ea='Earts:BAAALgAECgYJBgAAAA==.',
Ec='Ecowolf:BAAALgADCgkJCQABLgADCgkJNwABAAAAAA==.',
Ed='Edgyname:BAABLgAECn8UAAIeAAcJBCASMwD5AQAeAAcJBCASMwD5AQAAAA==.Edgyvoid:BAAALgADCgYJDAAAAA==.Edlund:BAABLgAECn8jAAIJAAkJfQ1jCACqAQAJAAkJfQ1jCACqAQAAAA==.',
Ef='Effyinzpjake:BAAALgAECgYJDgAAAA==.',
Ei='Eianistic:BAAALgADCgEJAQAAAA==.',
El='Elbiee:BAAALgAECggJCAABLgAECgkJFAAZACIZAA==.Eleos:BAAALgAECgYJDAAAAA==.Elfvispresly:BAAALgAECgEJAQABLgAECgkJDwABAAAAAA==.Ellenee:BAAALgADCgMJAwAAAA==.Ellinor:BAAALgADCgkJNwAAAA==.Elvy:BAABLgAECn8wAAIDAAkJNxkbGgD7AQADAAkJNxkbGgD7AQAAAA==.',
En='Enngin:BAAALgAFFAMJBAAAAA==.Enragee:BAAALgAECgEJAwABLgAECgcJGQAOAIUiAA==.Enroks:BAAALgAECgUJBQAAAA==.',
Er='Erebus:BAAALgAECgYJDAAAAA==.Erythra:BAAALgAECgQJBAAAAA==.',
Eu='Euphoría:BAAALgADCgIJAgAAAA==.',
Ev='Evildefiant:BAAALgAECgEJAQAAAA==.Evilfoxx:BAAALgADCgQJBQAAAA==.',
Ex='Exsalsior:BAAALgADCgYJBgAAAA==.',
Ey='Eyedoc:BAAALgADCgQJBAAAAA==.',
Fa='Fabulousness:BAABLgAECn8vAAIVAAkJCiHoBAAxAwAVAAkJCiHoBAAxAwAAAA==.',
Fe='Fearliz:BAAALgADCgEJAQAAAA==.Felmina:BAAALgADCgkJCQAAAA==.',
Fi='Fifefrost:BAAALgAECgQJBAAAAA==.Fishingsucks:BAAALgAECgcJCgAAAA==.Fiurich:BAAALgAFFAEJAQAAAA==.',
Fl='Flexi:BAAALgADCgEJAQAAAA==.Flitred:BAAALgAECggJDwAAAA==.Flock:BAAALgAECgcJEwAAAA==.',
Fo='Foxx:BAAALgAECgUJDQAAAA==.',
Fr='Framboise:BAABLgAECn8ZAAICAAYJUQcaYAAwAQACAAYJUQcaYAAwAQAAAA==.Frostybolt:BAAALgAECgUJBwAAAA==.',
Fu='Furryosa:BAAALgADCgUJBQAAAA==.Furryriver:BAAALgAECgcJEAAAAA==.Furytotem:BAABLgAECn8XAAIZAAgJiBOmAgCqAQAZAAgJiBOmAgCqAQABLgABCgIJAgABAAAAAA==.',
['Fø']='Føxx:BAAALgAECgEJAQAAAA==.',
Ga='Galadhras:BAAALgADCgYJFAAAAA==.Galdryn:BAAALgADCgIJAQAAAA==.Galianna:BAABLgAECn8XAAIVAAgJmxI1IQC5AQAVAAgJmxI1IQC5AQAAAA==.Gamboslice:BAACLgAFFH8FAAIRAAIJzgabDQB0AAARAAIJzgabDQB0AAAuAAQKfx8AAhEACQn+FgICAEUBABEACQn+FgICAEUBAAAA.Garkevon:BAAALgAECgQJAwAAAA==.',
Ge='Gemeni:BAAALgAECgEJAQAAAA==.Gevul:BAACLgAFFH8LAAMTAAUJMwzXIwDHAAATAAQJMwzXIwDHAAAWAAEJAACyEwAAAAAuAAQKf2kAAxMACQnyG6YZAIoCABMACQnfG6YZAIoCAAsABAnlEwMkAJIAAAAA.',
Gh='Ghostess:BAAALgADCgkJAQAAAA==.Ghrank:BAABLgAECn8jAAQTAAgJyw7bBQBaAQATAAgJyw7bBQBaAQAWAAYJHwgMHQDWAAALAAYJ8QcHIgCfAAAAAA==.',
Gi='Gilliruni:BAAALgADCgUJBQAAAA==.Gitpull:BAAALgAECggJDgAAAA==.',
Gl='Glazul:BAAALgAECgUJBwAAAA==.Glimley:BAAALgADCgMJAwAAAA==.',
Gn='Gnimsh:BAAALgAECgEJAwAAAA==.Gnorst:BAAALgADCgkJCgAAAA==.',
Go='Goodfoxx:BAAALgAECgEJAQAAAA==.Goreolio:BAAALgADCgkJDwABLgAECgYJEQABAAAAAA==.',
Gr='Grandmatank:BAAALgADCgkJCQAAAA==.Grasshopaa:BAAALgADCgYJCQAAAA==.Grassy:BAAALgADCgkJCQAAAA==.Greengoatlin:BAAALgADCgcJBwAAAA==.Gremlock:BAAALgAFFAEJAQAAAA==.Gremz:BAABLgAECn8mAAIcAAkJCQrEEABAAQAcAAkJCQrEEABAAQAAAA==.Grozny:BAAALgAECgQJBAAAAA==.Grày:BAABLgAECn8wAAIMAAkJXx2nIQCBAgAMAAkJXx2nIQCBAgAAAA==.',
Gu='Gumboslice:BAACLgAFFH8TAAMEAAYJdg/MJgAmAQAEAAYJdg/MJgAmAQADAAEJLgXfIgAvAAAuAAQKfx8AAgQACQnSHYALAAcDAAQACQnSHYALAAcDAAAA.Gusgus:BAABLgAECn8qAAIFAAkJRwx1BwCEAQAFAAkJRwx1BwCEAQAAAA==.',
['Gä']='Gändälf:BAABLgAECn8XAAIkAAgJvxXFBACgAQAkAAgJvxXFBACgAQAAAA==.',
Ha='Habanero:BAABLgAECn8qAAMOAAkJSA+rPAC8AQAOAAkJSA+rPAC8AQAZAAQJUxhuTgD8AAAAAA==.Hachedev:BAAALgAECgMJCAAAAA==.Hadrîan:BAAALgADCgcJCQAAAA==.Hadtopandadk:BAAALgAECgcJDQAAAA==.Hallia:BAACLgAFFH8GAAIEAAMJ9BHjQACtAAAEAAMJ9BHjQACtAAAuAAQKfzgAAgQACQlTGjcTALECAAQACQlTGjcTALECAAAA.Hark:BAAALgADCgkJOgAAAA==.Harrybob:BAAALgADCgcJCgAAAA==.Havvocchi:BAAALgAECgEJAwAAAA==.Hawgmane:BAAALgAECgUJBQAAAA==.Hawgwild:BAABLgAECn8mAAIMAAkJKxDNYgCiAQAMAAkJKxDNYgCiAQAAAA==.',
He='Headdinks:BAAALgADCgcJDAAAAA==.Healcap:BAAALgADCgQJBAAAAA==.Healvisprsly:BAABLgAECn8dAAQEAAkJxhgWKgAEAgAEAAgJlxoWKgAEAgADAAYJ9BgHJgCcAQAiAAMJ3hlwMgDfAAAAAA==.Heisenberg:BAAALgADCgMJAwABLgAECgMJBwABAAAAAA==.Helena:BAABLgAECn9EAAMHAAkJFSSKBgA8AwAHAAkJEySKBgA8AwAIAAkJUB5sBQCbAgAAAA==.Heliarc:BAAALgADCgkJOwAAAA==.Hermès:BAAALgAECgUJBgABLgAFFAcJGgAMAJMiAA==.',
Hi='Highfive:BAAALgAECgUJCwAAAA==.',
Ho='Holybeech:BAAALgAECgQJBAAAAA==.Honestly:BAAALgAFFAIJBAAAAA==.Honkytonkman:BAAALgADCgQJBAAAAA==.Hover:BAAALgAECgYJEQAAAA==.',
Ih='Ihmoen:BAAALgADCgYJBgAAAA==.',
Il='Illuminate:BAAALgADCgQJBAAAAA==.Illustria:BAAALgADCgkJKgABLgAECgYJBgABAAAAAA==.Illustriâ:BAAALgADCgkJFgABLgAECgYJBgABAAAAAA==.Illustriä:BAAALgAECgYJBgAAAA==.',
Im='Imprison:BAAALgAECgYJBgABLgAECggJGAAFAJUaAA==.',
In='Insidious:BAABLgAECn8fAAIgAAkJFRrLDwAPAgAgAAkJFRrLDwAPAgAAAA==.Invoke:BAAALgADCgEJAQAAAA==.',
Ir='Irs:BAAALgAECgUJBwAAAA==.',
Is='Isisvane:BAAALgAECgUJBwAAAA==.',
It='Itchyfeet:BAAALgAECgUJCAABLgAFFAYJHAAFAFcfAA==.Itchymage:BAACLgAFFH8cAAIFAAYJVx9SOgCBAQAFAAYJVx9SOgCBAQAuAAQKfycAAgUACQnIIzMdAAEDAAUACQnIIzMdAAEDAAAA.Itchyw:BAAALgAFFAEJAQABLgAFFAYJHAAFAFcfAA==.',
Ja='Jacckiemoon:BAAALgAECgQJBAABLgAECgkJHQAEAMYYAA==.Jadehunterr:BAAALgAECgMJBAAAAA==.Jaesn:BAAALgADCgYJBgAAAA==.',
Je='Jeldon:BAAALgADCgQJBAAAAA==.Jenae:BAAALgAECgEJAQAAAA==.Jenövha:BAAALgADCgkJFwAAAA==.Jezebelle:BAAALgAECgUJBQAAAA==.',
Ji='Jighlipuff:BAAALgAECgIJAgAAAA==.Jigs:BAACLgAFFH8FAAIQAAEJOhthVgBJAAAQAAEJOhthVgBJAAAuAAQKf0wAAhAACQlNGkQgAGYCABAACQlNGkQgAGYCAAAA.Jinxy:BAAALgAECgMJAwABLgAECgUJBQABAAAAAA==.Jiräiya:BAAALgADCgYJBgAAAA==.',
Jo='Johastrasz:BAAALgADCggJCAAAAA==.',
Ju='Junsing:BAAALgADCgEJAQABLgAFFAEJAQABAAAAAA==.',
['Jå']='Jåfar:BAAALgADCgEJAgAAAA==.',
Ka='Kabøchi:BAAALgAECgUJBQAAAA==.Kafia:BAAALgAECgEJAgAAAA==.Kaladriel:BAAALgADCgEJAQAAAA==.Kaldrick:BAABLgAECn8hAAMZAAkJ4xXoGwACAgAZAAkJZBToGwACAgAaAAEJzheXCwBFAAAAAA==.Kamstareater:BAABLgAECn8mAAIeAAkJ+hLbPgDNAQAeAAkJ+hLbPgDNAQAAAA==.Kanakas:BAABLgAECn8UAAIGAAkJohtXHQAYAgAGAAkJohtXHQAYAgAAAA==.Kanaloa:BAABLgAECn8pAAIFAAkJ1gkKeACJAQAFAAkJ1gkKeACJAQAAAA==.Kayler:BAAALgAECgYJBgABLgAECgYJCwABAAAAAA==.',
Ke='Kegerator:BAAALgAECgUJBgAAAA==.Keirin:BAAALgAECggJEgAAAA==.Keldica:BAAALgAECgYJBwABLgAECgYJFAAFANQfAA==.Kelemver:BAAALgADCgMJAwAAAA==.Kelysa:BAAALgAECggJDwAAAA==.Kena:BAAALgADCgUJBQAAAA==.Kenshan:BAAALgAECgMJAwAAAA==.Kevinbox:BAAALgAECgYJEAAAAA==.Kevinslayer:BAAALgAECgUJDAAAAA==.Keynaridan:BAABLgAECn8ZAAIeAAgJ1xJHVACJAQAeAAgJ1xJHVACJAQAAAA==.Keyss:BAAALgADCgIJAgAAAA==.',
Kg='Kglizard:BAAALgAECgUJCAAAAA==.',
Kh='Khalinor:BAABLgAECn8lAAIGAAkJXhcPEgCCAgAGAAkJXhcPEgCCAgAAAA==.Khardun:BAAALgAECgEJAQAAAA==.Khotuhn:BAAALgAECgYJEQAAAA==.',
Ki='Kickazdin:BAACLgAFFH8MAAIGAAQJShz8GABbAQAGAAQJShz8GABbAQAuAAQKfyIAAwYACQm7HisHABkDAAYACQm7HisHABkDAAcAAgkFCllDAWkAAAAA.Killadragon:BAAALgADCgUJBQAAAA==.Kiryie:BAABLgAECn8bAAIQAAkJDA8cXgCMAQAQAAkJDA8cXgCMAQAAAA==.Kisäme:BAAALgAECggJCwAAAA==.',
Kl='Klad:BAAALgAECgEJAwAAAA==.Klaw:BAAALgADCgkJCQAAAA==.Kluma:BAAALgAECgEJAQAAAA==.',
Kn='Knok:BAAALgAECggJCAAAAA==.',
Ko='Kobu:BAAALgADCgUJBgAAAA==.Konran:BAAALgADCgEJAQAAAA==.',
Kp='Kprist:BAAALgAECgEJAQAAAA==.',
Kr='Kraigen:BAABLgAECn8wAAIdAAkJLh6WBwC3AgAdAAkJLh6WBwC3AgAAAA==.Krinack:BAABLgAECn8lAAIXAAkJfBLGFgDnAQAXAAkJfBLGFgDnAQAAAA==.Krixiz:BAAALgAECgYJCgAAAA==.',
Ks='Kshamify:BAABLgAFFH8HAAIOAAMJzBMuVwCgAAAOAAMJzBMuVwCgAAAAAA==.',
Ku='Kurindrixx:BAAALgADCgIJAgAAAA==.Kurtakum:BAAALgADCgMJAwAAAA==.Kutiel:BAABLgAECn8ZAAMZAAcJUgrdUAD0AAAZAAcJUgrdUAD0AAAOAAEJtQn3JQAnAAAAAA==.',
Kw='Kwarify:BAAALgADCgEJAQAAAA==.',
Ky='Kynasmira:BAAALgADCgkJIgAAAA==.Kyrsh:BAAALgADCgcJEAAAAA==.',
La='Ladrona:BAABLgAECn8ZAAIlAAkJ+B0lAgDHAgAlAAkJ+B0lAgDHAgAAAA==.Lailyre:BAAALgAECgYJCwAAAA==.Lassan:BAAALgAECgYJCQAAAA==.Later:BAAALgAECggJDAAAAA==.Latimir:BAAALgAECgIJAgAAAA==.Laur:BAAALgADCgYJBgAAAA==.Lavendeer:BAABLgAECn8nAAIDAAkJDhQBHwDQAQADAAkJDhQBHwDQAQAAAA==.Laydin:BAAALgAECgkJCAABLgAECgkJKAAEAMgDAA==.Laylana:BAAALgAECgEJAQAAAA==.Lazyeye:BAAALgADCgUJBAABLgAECgcJDgABAAAAAA==.',
Lb='Lb:BAAALgADCgUJBgABLgAECgkJFAAZACIZAA==.',
Le='Legume:BAAALgADCgcJCAABLgAECgUJDQABAAAAAA==.Legzanot:BAACLgAFFH8WAAIZAAQJGgtvFQCtAAAZAAQJGgtvFQCtAAAuAAQKfygAAhkACQkyFiQdACgCABkACQkyFiQdACgCAAAA.Leonceault:BAAALgAECgEJAQAAAA==.',
Li='Lifebringa:BAABLgAECn8sAAMVAAgJTh9pCwCwAgAVAAcJ4yJpCwCwAgAjAAcJxhWmJgCXAQAAAA==.Lightningfox:BAABLgAECn80AAMHAAkJVxqEBADjAQAHAAkJVxqEBADjAQAGAAIJug7vdABmAAAAAA==.Lightsfallen:BAAALgAECgkJDwAAAA==.Lileth:BAAALgAECgYJBAAAAA==.Lilylulu:BAAALgADCgIJAgAAAA==.Limzzmagus:BAAALgAECgMJBgAAAA==.Liriel:BAAALgADCgMJAwABLgAECgUJBQABAAAAAA==.Lithia:BAABLgAECn8bAAIMAAkJzQ94cgB/AQAMAAkJzQ94cgB/AQAAAA==.Littlemo:BAAALgAECgcJEAAAAA==.',
Lo='Loggs:BAAALgAFFAEJAQAAAA==.Lohnar:BAAALgAECgcJEAAAAA==.Lornah:BAAALgADCgQJBAAAAA==.',
Lu='Lucidslock:BAAALgADCgIJAgAAAA==.Lucielbaal:BAABLgAECn8sAAITAAkJ9R4LDwDUAgATAAkJ9R4LDwDUAgAAAA==.Luciferus:BAAALgAECgUJCAABLgAFFAIJBgAUAOMGAA==.Luckystop:BAABLgAECn8ZAAMOAAcJhSJXFACpAgAOAAcJhSJXFACpAgAZAAQJNwqOagCoAAAAAA==.Lumenir:BAAALgAECgEJAQAAAA==.Lunareth:BAAALgAECgQJBAAAAA==.Luraris:BAAALgAECgEJAQAAAA==.',
Ly='Lyrska:BAABLgAECn8vAAIUAAkJLRETFAAEAgAUAAkJLRETFAAEAgAAAA==.Lytearrow:BAABLgAECn8nAAIQAAgJRA8bYQCEAQAQAAgJRA8bYQCEAQAAAA==.',
['Lè']='Lèonidas:BAAALgAECgEJAwABLgAECgkJMQAiAEgXAA==.',
['Lé']='Léaf:BAAALgAECgMJAwAAAA==.',
Ma='Madfaith:BAAALgADCgEJAQAAAA==.Mahrylee:BAAALgAECgcJEAAAAA==.Maiya:BAAALgADCgcJEAAAAA==.Majutsu:BAAALgADCgEJAQABLgADCgcJDgABAAAAAA==.Malbrax:BAABLgAECn8ZAAITAAgJcxIzVACfAQATAAgJcxIzVACfAQAAAA==.Maleficents:BAABLgAECn8uAAIDAAcJZRN6LgBnAQADAAcJZRN6LgBnAQAAAA==.Malurius:BAABLgAECn8bAAMmAAkJshSzEADoAQAmAAkJsRKzEADoAQACAAYJ4AosZwDBAAAAAA==.Malware:BAAALgAECgYJEQAAAA==.Manana:BAAALgADCgEJAQAAAA==.Manbearpally:BAAALgAECgQJBAAAAA==.Manikfury:BAABLgAECn8iAAMhAAgJwBu6CQAmAgAhAAgJwBu6CQAmAgAEAAYJYx5ZLQDxAQAAAA==.Maniksmage:BAAALgAECggJEgABLgAECggJIgAhAMAbAA==.Mannypack:BAABLgAECn8eAAQDAAgJixwTFQAoAgADAAgJixwTFQAoAgAEAAQJkAz6gQC1AAAiAAEJOxOocAA3AAAAAA==.Maranelli:BAAALgAECgIJAwAAAA==.Maseles:BAAALgAECgUJBgABLgAECgUJCQABAAAAAA==.Maxiticon:BAABLgAECn8XAAQjAAYJTQi8YACWAAAjAAUJ0QW8YACWAAAVAAUJogXVVACJAAAYAAEJnQ73egAwAAAAAA==.',
Mc='Mcdawg:BAAALgADCgYJCgAAAA==.Mcleary:BAAALgAECgYJCQAAAA==.',
Me='Meldrus:BAAALgAECgQJBAAAAA==.Melinashala:BAABLgAECn9DAAITAAkJNgZkCgDzAAATAAkJNgZkCgDzAAAAAA==.Mending:BAAALgAECgYJCwAAAA==.Meowinator:BAAALgAECgYJDQAAAA==.Mephizto:BAAALgAECgYJCQAAAA==.Metide:BAAALgAECgQJBAAAAA==.',
Mi='Miala:BAAALgAECgEJAQAAAA==.Mierna:BAAALgAECgkJEgAAAA==.Miler:BAAALgAECggJCgAAAA==.Millylittle:BAAALgADCgUJBQAAAA==.Minisor:BAAALgAECgUJBQAAAA==.Minx:BAAALgADCgIJAQAAAA==.Misanth:BAAALgAECgYJDgAAAA==.Mistdruid:BAAALgAECgIJAwABLgAECgIJBgABAAAAAA==.',
Mo='Moemo:BAABLgAECn8qAAIEAAkJ5CAqAQCCAgAEAAkJ5CAqAQCCAgAAAA==.Mogryn:BAAALgAECgkJEwAAAA==.Moistymists:BAAALgAECgYJCQAAAA==.Moll:BAAALgADCgEJAQAAAA==.Mommybree:BAAALgAECgYJEgAAAA==.Monksterz:BAABLgAECn8wAAIPAAkJfCEnBgDaAgAPAAkJfCEnBgDaAgAAAA==.Monophobic:BAAALgAECgcJBwAAAA==.Monoxidê:BAAALgAECgEJAQAAAA==.Moonwarriorx:BAAALgAECggJDAAAAA==.Morsecode:BAABLgAECn8lAAILAAkJPRfHCAC+AQALAAkJPRfHCAC+AQABLgABCgIJAgABAAAAAA==.Morthok:BAABLgAECn8rAAITAAgJCBhOOwDtAQATAAgJCBhOOwDtAQAAAA==.Mortischa:BAAALgADCggJCwAAAA==.Mosh:BAABLgAECn8bAAIPAAkJDhQSGgDVAQAPAAkJDhQSGgDVAQAAAA==.',
Mu='Muchuchu:BAAALgAECgUJEQABLgAECgIJAgABAAAAAA==.Muldern:BAAALgAECgEJAQAAAA==.Munkee:BAAALgAECgYJEQAAAA==.Murdinbronze:BAAALgADCgUJCAAAAA==.Mustachekick:BAAALgAECgUJBQAAAA==.Musyl:BAAALgADCgEJAQABLgAECgYJEQABAAAAAA==.',
['Mã']='Mãf:BAABLgAECn8kAAMOAAgJVxH6VABhAQAOAAgJVxH6VABhAQAZAAEJtxx2kABRAAAAAA==.',
['Mí']='Místwalker:BAAALgAECgIJBgAAAA==.',
Na='Nackthyr:BAACLgAFFH8cAAMJAAUJCiYnAQCyAQAJAAUJCiYnAQCyAQAKAAIJNRvOTACbAAAuAAQKfz0AAgkACQmxJkcAAHcDAAkACQmxJkcAAHcDAAAA.Naelyn:BAAALgAECgEJAQAAAA==.Nafir:BAAALgADCgYJFwAAAA==.Nakky:BAAALgAECgYJDgAAAA==.Narlin:BAAALgAECgYJCQAAAA==.Nasta:BAABLgAECn8bAAIHAAYJ6Qhc4QDcAAAHAAYJ6Qhc4QDcAAAAAA==.Natureboi:BAAALgADCgQJBAABLgADCgYJDAABAAAAAA==.Nazareths:BAAALgAECgQJCwAAAA==.Nazgor:BAABLgAECn8VAAIMAAgJ9BbPCQAtAQAMAAgJ9BbPCQAtAQAAAA==.Nazrien:BAAALgAECgUJBQAAAA==.',
Ne='Neckromancy:BAAALgAECgYJCgAAAA==.Necrosius:BAAALgAECgYJDwAAAA==.Neonarc:BAEALgADCgkJMgAAAA==.Neshi:BAAALgAECgMJBQAAAA==.Neuman:BAAALgADCgEJAQAAAA==.Neval:BAAALgAECgcJCQABLgAFFAcJGgAUABYSAA==.',
Ni='Nibblemah:BAAALgAECgcJCwAAAA==.Nightsbane:BAAALgADCgcJFgAAAA==.Nikmonk:BAAALgAECgUJBQABLgAECgkJLgAdAD8fAA==.Nivdk:BAAALgADCgYJBgABLgAECgYJEQABAAAAAA==.Nivora:BAAALgAECgYJEQAAAA==.',
No='Notsure:BAABLgAECn8iAAINAAkJ4wWOBQCwAAANAAkJ4wWOBQCwAAAAAA==.',
Nu='Nutt:BAAALgAECgEJAQAAAA==.',
Ny='Nyxstalia:BAAALgAECgUJDAAAAA==.Nyyx:BAABLgAECn8jAAIeAAgJMwg5nQDnAAAeAAgJMwg5nQDnAAAAAA==.',
['Ná']='Nácl:BAAALgAFFAEJAQABLgAFFAUJHAAJAAomAA==.',
Oa='Oath:BAAALgAECgUJBQAAAA==.',
Ob='Obscyra:BAAALgAFFAEJAQAAAA==.',
Ol='Olmek:BAACLgAFFH8fAAICAAgJcRq6AwC4AQACAAgJcRq6AwC4AQAuAAQKfx4AAgIABwk7JlQPAIACAAIABwk7JlQPAIACAAAA.',
Oo='Oochie:BAAALgADCgQJAwAAAA==.Oonagi:BAAALgAECgUJBQAAAA==.',
Op='Opalana:BAAALgADCgIJAwAAAA==.Ophiana:BAAALgAECgEJAwAAAA==.Oprahwndfury:BAAALgAECgYJEQABLgAECgkJHQAEAMYYAA==.',
Or='Orasaya:BAAALgADCgYJBgAAAA==.Orphee:BAAALgADCgcJBwAAAA==.Orzanis:BAAALgADCgcJDgAAAA==.',
Ow='Owlcapone:BAAALgADCgEJAQAAAA==.',
Pa='Paige:BAAALgADCgcJDgAAAA==.Palasades:BAAALgADCgUJBQAAAA==.Pallymarc:BAAALgADCgcJCwAAAA==.Pallytune:BAACLgAFFH8QAAIGAAMJPxPYLQDDAAAGAAMJPxPYLQDDAAAuAAQKfxwAAgYACQnxDi0lAN0BAAYACQnxDi0lAN0BAAEuAAUUBAkFAAQA6QIA.Pandalorian:BAAALgAECgYJEAAAAA==.Pandamajack:BAAALgAECggJEwAAAA==.Pandore:BAAALgAECgYJBgAAAA==.Paîîy:BAAALgADCgIJAgAAAA==.',
Ph='Philandre:BAABLgAECn8mAAIHAAkJ9RNvYgCrAQAHAAkJ9RNvYgCrAQAAAA==.',
Pi='Picoso:BAABLgAECn8iAAIFAAkJrw36aQCoAQAFAAkJrw36aQCoAQAAAA==.Piianca:BAAALgAECgUJBgAAAA==.Piianna:BAABLgAECn8ZAAIVAAcJoBucGwDrAQAVAAcJoBucGwDrAQAAAA==.Pirko:BAAALgADCggJCwAAAA==.',
Po='Pocketheal:BAAALgADCgkJEAAAAA==.',
Pr='Probzedgy:BAAALgAECgQJBAAAAA==.',
Pt='Pteradactyl:BAAALgAECgYJBgAAAA==.',
Pu='Punch:BAAALgAECgEJAgAAAA==.Punchingfox:BAAALgAECgEJAQAAAA==.Purgespam:BAAALgAECgEJAQAAAA==.Purplerain:BAAALgAECgUJBgAAAA==.Putrigord:BAAALgAECgQJCwAAAA==.',
Py='Pylarthius:BAAALgADCgcJBwAAAA==.',
Qi='Qik:BAAALgAECgEJAQAAAA==.Qikkaw:BAABLgAECn82AAMOAAkJLBEbCgAGAQAOAAkJLBEbCgAGAQAZAAcJHQskCQDBAAAAAA==.Qitetsu:BAAALgAECgUJBgAAAA==.',
Qu='Quantos:BAABLgAECn9GAAIiAAkJ7BB0AwBHAQAiAAkJ7BB0AwBHAQAAAA==.Qulight:BAAALgAECgQJBAABLgAECgkJLwAYACsfAA==.Ququmatz:BAAALgADCgMJAwAAAA==.',
Ra='Raatha:BAABLgAECn8hAAIHAAkJeRY6NAAvAgAHAAkJeRY6NAAvAgAAAA==.Raeyla:BAAALgAECgcJEwAAAA==.Raganar:BAABLgAECn9GAAIIAAkJhRU4AQDtAQAIAAkJhRU4AQDtAQAAAA==.Ranlerodis:BAAALgADCgMJAwAAAA==.Rayjean:BAAALgADCgkJIwAAAA==.',
Re='Redneckboots:BAAALgADCgEJAQAAAA==.Relmax:BAABLgAECn8fAAINAAgJKwoFIgAgAQANAAgJKwoFIgAgAQAAAA==.Rendeminae:BAAALgADCgcJBwAAAA==.Renri:BAABLgAECn8eAAIXAAcJFBZUHwCbAQAXAAcJFBZUHwCbAQAAAA==.Repose:BAAALgAECgIJAwAAAA==.Revick:BAAALgAECgUJCAAAAA==.Revil:BAAALgADCgIJAgAAAA==.',
Rh='Rhaenýs:BAAALgADCgcJDQAAAA==.Rhonwynn:BAABLgAECn8/AAIOAAkJEh78AQBbAgAOAAkJEh78AQBbAgAAAA==.',
Ri='Rikershipdwn:BAABLgAECn8ZAAIQAAgJQRRpTgC3AQAQAAgJQRRpTgC3AQAAAA==.Rikersline:BAAALgADCgkJCQAAAA==.Rimish:BAABLgAECn8cAAMGAAkJCRU8FgBaAgAGAAkJCRU8FgBaAgAHAAEJNRvDLwBQAAAAAA==.Rimrave:BAABLgAECn8qAAQmAAkJnh0IBwCKAgAmAAkJJRwIBwCKAgACAAYJIxscNQDVAQANAAYJiB0LGgBqAQAAAA==.Ripavicii:BAAALgAECgEJAQAAAA==.Ritobeans:BAAALgADCgkJOgAAAA==.Rivik:BAAALgAFFAEJBAAAAA==.',
Ro='Robbstark:BAAALgAECgYJDAAAAA==.Robertkenway:BAACLgAFFH8GAAIUAAIJ4wbYDQB2AAAUAAIJ4wbYDQB2AAAuAAQKfy4AAxQACAmnEKEcALgBABQACAmnEKEcALgBABAAAQkAANfUADAAAAAA.Roguebot:BAAALgADCgkJEgAAAA==.Rohdaric:BAABLgAECn8ZAAIUAAYJUxTNFgBdAQAUAAYJUxTNFgBdAQAAAA==.Rokte:BAABLgAECn8bAAIWAAkJ0w+iDACSAQAWAAkJ0w+iDACSAQAAAA==.Rollhots:BAAALgAECgYJBgAAAA==.Roo:BAAALgAECgEJAwAAAA==.Rook:BAABLgAECn8nAAQLAAgJNyN2BAA2AgATAAgJxCGuFACpAgALAAcJcyB2BAA2AgAWAAEJAAC5SQAAAAABLgAFFAEJAQABAAAAAA==.Rookeh:BAAALgAFFAEJAQAAAA==.Rosekenway:BAABLgAECn81AAMEAAkJ0Rc9AQByAgAEAAkJ0Rc9AQByAgADAAUJ4Qn5aQB5AAABLgAFFAIJBgAUAOMGAA==.',
Rr='Rratt:BAAALgAECgYJEAAAAA==.',
Ru='Rubimoon:BAAALgAECgUJBQAAAA==.Rumí:BAAALgAECggJCAAAAA==.Running:BAAALgAECgIJAgAAAA==.',
['Rú']='Rúfus:BAAALgADCgYJBwAAAA==.',
Sa='Saammiee:BAAALgAECgMJBAAAAA==.Sabiha:BAABLgAECn8UAAMQAAYJaA+qZQA2AQAQAAYJaA+qZQA2AQAfAAEJwQPplAAlAAAAAA==.Safewaybag:BAAALgADCgQJBAAAAA==.Saintb:BAAALgAECgUJBAAAAA==.Saintotem:BAABLgAECn8mAAIZAAkJ3xGeJgC2AQAZAAkJ3xGeJgC2AQAAAA==.Samartyr:BAAALgAECgYJCQAAAA==.Samison:BAAALgAECgYJBgAAAA==.Sammiiee:BAAALgADCgQJBAABLgAECgMJBAABAAAAAA==.Sandii:BAAALgADCgkJCgAAAA==.Sangwynaris:BAAALgAECgcJDgAAAA==.Sanilien:BAAALgAECgYJBgAAAA==.Saphiiraa:BAABLgAECn8oAAInAAkJZxIfDgDsAQAnAAkJZxIfDgDsAQAAAA==.Sayahealer:BAAALgADCgcJDgAAAA==.',
Sc='Scorpmage:BAABLgAECn8tAAIFAAkJphjISQD+AQAFAAkJphjISQD+AQAAAA==.Scramms:BAAALgADCgcJDQAAAA==.Scrams:BAABLgAECn8VAAIfAAcJpwxdFgAFAQAfAAcJpwxdFgAFAQAAAA==.',
Se='Sedrick:BAABLgAECn9PAAMGAAkJZSDIAACRAgAGAAkJZSDIAACRAgAHAAcJyBW6cgCIAQAAAA==.Sekendipity:BAAALgADCgEJAQABLgAECgcJDgABAAAAAA==.Sekhmett:BAAALgADCgMJAwAAAA==.Sekndestroy:BAAALgADCgYJCQABLgAECgcJDgABAAAAAA==.Sektacular:BAAALgADCgQJBAABLgAECgcJDgABAAAAAA==.Sekzen:BAAALgAECgcJDgAAAA==.Semiazas:BAABLgAECn8/AAQWAAkJtQ/8AAC6AQAWAAkJtQ/8AAC6AQATAAUJ2QmotwDpAAALAAEJAAD7egAnAAAAAA==.Semiazes:BAAALgADCgYJBgAAAA==.Senessa:BAAALgADCgIJAgAAAA==.Sensy:BAAALgAECgQJCQAAAA==.Sepulveda:BAAALgAECgUJBQABLgAECgkJKgAEAOQgAA==.Serwonton:BAAALgADCgUJBQAAAA==.Seumas:BAAALgADCgMJAwAAAA==.',
Sh='Shadrock:BAAALgADCgYJBgAAAA==.Shaio:BAAALgADCgEJAQAAAA==.Shamtune:BAAALgAECgQJBAABLgAFFAQJBQAEAOkCAA==.Sharayman:BAAALgADCgkJDgABLgADCgkJIwABAAAAAA==.Shattered:BAABLgAECn8hAAIcAAkJTxt+AABpAgAcAAkJTxt+AABpAgAAAA==.Shayrisa:BAABLgAECn9JAAMZAAkJAhUIAgDqAQAZAAkJAhUIAgDqAQAOAAkJTBIzBwBLAQAAAA==.Shazool:BAABLgAECn8cAAMOAAkJlB7rEgC1AgAOAAkJlB7rEgC1AgAaAAIJkQtPMgBoAAABLgAFFAMJBgAEAPQRAA==.Sheep:BAABLgAECn8YAAMFAAgJlRpsSwD5AQAFAAgJshlsSwD5AQAkAAIJmBkAFABMAAAAAA==.Shifterz:BAAALgAECgcJDwAAAA==.Shrieke:BAAALgAECgYJCQAAAA==.Shrubbery:BAABLgAECn8fAAIiAAgJpBEmHABtAQAiAAgJpBEmHABtAQAAAA==.Shxdow:BAAALgAECgQJBAAAAA==.',
Si='Sind:BAABLgAECn8bAAIIAAgJRhaZDwDKAQAIAAgJRhaZDwDKAQABLgAECgkJMQAiAEgXAA==.Sindella:BAAALgAECgYJDQABLgAECgkJMQAiAEgXAA==.Sindrè:BAAALgADCgQJBQABLgAECgkJMQAiAEgXAA==.Sinna:BAAALgADCgUJCQABLgAECgEJAQABAAAAAA==.Sinthorne:BAABLgAECn8xAAMiAAkJSBfrAgBmAQAiAAkJSBfrAgBmAQAhAAMJ8AW9PQBjAAAAAA==.',
Sk='Skedaddle:BAAALgAECgYJCwABLgAECgkJPwAFAEYkAA==.Skithíryx:BAAALgAECgcJDwAAAA==.Skoodal:BAAALgADCgIJAgAAAA==.Skylight:BAAALgAECgEJAQAAAA==.',
Sl='Slashbndcoot:BAAALgAFFAMJAwAAAA==.Slashgquit:BAACLgAFFH8SAAIgAAQJniDZEwBSAQAgAAQJniDZEwBSAQAuAAQKfzUAAiAACQmIJOYDAPwCACAACQmIJOYDAPwCAAAA.Slumbermist:BAABLgAECn8+AAMSAAkJxhEzHgC8AQASAAkJxhEzHgC8AQAbAAcJgxJLCAA9AQABLgABCgIJAgABAAAAAA==.',
So='Solaire:BAABLgAECn8hAAMIAAcJWRzfEAC2AQAIAAcJWRzfEAC2AQAGAAUJqRDSTwD6AAABLgAFFAQJCQASAMQiAA==.Soras:BAAALgADCgkJHwAAAA==.Sourjack:BAAALgAECgUJBgAAAA==.',
St='Steph:BAAALgAECgUJBQAAAA==.',
Su='Sunareas:BAAALgADCgIJAgAAAA==.',
Sy='Syndar:BAAALgAECgMJAwABLgAECgYJFAAFANQfAA==.Synthetic:BAABLgAECn8nAAILAAkJWxYHCADPAQALAAkJWxYHCADPAQAAAA==.Syrebriel:BAAALgADCgEJAgABLgAECgcJGQAZAFIKAA==.',
Sz='Szasstaam:BAABLgAECn8kAAMkAAkJ4wc+BwA9AQAkAAkJ4wc+BwA9AQAFAAQJGQIAJwFsAAAAAA==.',
['Sé']='Sénåtor:BAAALgADCgYJCAABLgAECgkJLwAHAHgUAA==.Séékér:BAAALgADCgcJFQAAAA==.',
Ta='Talanith:BAAALgADCggJEAAAAA==.Tarayk:BAAALgADCgYJCAABLgADCgkJIwABAAAAAA==.Taxal:BAAALgADCgYJBwAAAA==.Taxlock:BAABLgAECn8aAAITAAcJ9wmGmwAGAQATAAcJ9wmGmwAGAQAAAA==.',
Tb='Tbagjones:BAAALgAECgQJBAAAAA==.',
Te='Tecsaran:BAABLgAECn8UAAIFAAYJ1B/ebgD2AQAFAAYJ1B/ebgD2AQAAAA==.Tekis:BAAALgADCgEJAQAAAA==.Telz:BAAALgAECgYJCgAAAA==.Terania:BAAALgADCgIJAgAAAA==.',
Th='Thalira:BAABLgAECn8dAAQnAAgJQAfpGwAgAQAnAAgJQAfpGwAgAQAKAAcJTwIocACLAAAJAAQJrQGENQBpAAAAAA==.Thetowelie:BAAALgAECgEJAQAAAA==.',
Ti='Tibbz:BAAALgADCgIJAgAAAA==.Tiger:BAACLgAFFH8+AAQhAAkJECUBAACwAwAhAAkJECUBAACwAwAiAAQJiCLVDAArAQAEAAMJYhpwMwDgAAAuAAQKfyoAAyEACQnqJgUAABYEACEACQnqJgUAABYEAAQAAQm1C4TEAD8AAAAA.Tinkera:BAAALgAECgQJBAAAAA==.Tinnea:BAAALgAECgUJDgAAAA==.Titanosaurus:BAAALgAECgcJEAAAAA==.Tizzly:BAABLgAECn8rAAIFAAkJzQ5vagCnAQAFAAkJzQ5vagCnAQAAAA==.',
To='Torhilda:BAAALgAECgYJBgABLgAECgYJFAAFANQfAA==.Torridwells:BAABLgAECn8bAAIQAAkJdQ/RWgCVAQAQAAkJdQ/RWgCVAQAAAA==.',
Tr='Trad:BAAALgADCgYJBgAAAA==.Troag:BAABLgAECn8fAAIOAAkJdxz1GgBzAgAOAAkJdxz1GgBzAgAAAA==.Troagstar:BAABLgAECn8nAAIZAAkJ/BrlGwACAgAZAAkJ/BrlGwACAgAAAA==.',
Ts='Tsaesci:BAAALgADCgQJBgAAAA==.Tsynn:BAAALgADCgYJFAAAAA==.',
Ty='Tylerz:BAAALgAFFAEJAQAAAA==.Tyraana:BAACLgAFFH8JAAIdAAMJbRmCBwDxAAAdAAMJbRmCBwDxAAAuAAQKf0IAAx0ACQlPIJEFAOcCAB0ACQlPIJEFAOcCAB4ACAndFGVMAKABAAAA.Tyrinwar:BAAALgADCgYJDAAAAA==.Tyrmog:BAABLgAECn8fAAIMAAkJVQl/lgA7AQAMAAkJVQl/lgA7AQAAAA==.Tytus:BAAALgAECgUJBQAAAA==.',
Un='Unique:BAAALgAECgEJAQABLgAFFAYJGwACADkkAA==.',
Us='Ushas:BAABLgAECn8yAAMVAAkJChmrGQD+AQAVAAkJChmrGQD+AQAYAAQJqQXgWwCQAAAAAA==.Usmcshammy:BAAALgAECgYJEQAAAA==.',
Va='Vali:BAABLgAECn8sAAIfAAkJHB/vAgCyAgAfAAkJHB/vAgCyAgAAAA==.Valindrea:BAAALgAECgcJEAAAAA==.Vasrael:BAABLgAECn82AAMHAAkJshd3OwAWAgAHAAgJ/Bl3OwAWAgAGAAcJYRzcHQAUAgAAAA==.Vav:BAABLgAECn8UAAMQAAYJeBdqoQD/AAAQAAYJeBdqoQD/AAAUAAIJswzTYAA5AAAAAA==.',
Ve='Vecnis:BAAALgAECgIJAgAAAA==.Veliette:BAAALgAECgUJCwAAAA==.Verdena:BAAALgADCgcJBwABLgADCgkJIwABAAAAAA==.Vexen:BAABLgAECn8mAAMeAAkJPRRqAgDvAQAeAAkJIRRqAgDvAQAdAAIJyhb0CQCJAAAAAA==.',
Vi='Victaliste:BAAALgAECgQJBQAAAA==.Vithper:BAAALgAECggJEwAAAA==.',
Vn='Vnia:BAAALgAECgEJAQABLgAECgMJCAABAAAAAA==.',
Vo='Voidmuffinz:BAACLgAFFH8IAAIeAAMJ4gz0agC2AAAeAAMJ4gz0agC2AAAuAAQKfyMAAh4ACQkmGE4tABICAB4ACQkmGE4tABICAAAA.',
Vy='Vynis:BAAALgAECgcJDQABLgAFFAQJBQAEAOkCAA==.Vyrahildard:BAABLgAECn8tAAIHAAkJfRuWJwBlAgAHAAkJfRuWJwBlAgAAAA==.',
Wa='Wakkiq:BAAALgAECgEJAQAAAA==.Waringoutlaw:BAABLgAECn8UAAICAAcJYgGangA3AAACAAcJYgGangA3AAAAAA==.Wasteland:BAABLgAECn8rAAIgAAkJphEvGwCDAQAgAAkJphEvGwCDAQAAAA==.',
We='Weaselhunter:BAAALgAFFAIJAwABLgAFFAIJBwATAPAWAA==.Weasellock:BAACLgAFFH8HAAITAAIJ8BYikgCeAAATAAIJ8BYikgCeAAAuAAQKfxEAAhMABgm+GLR8AD8BABMABgm+GLR8AD8BAAAA.Weaselmage:BAAALgAFFAIJAgABLgAFFAIJBwATAPAWAA==.Welor:BAAALgADCgYJDAAAAA==.',
Wh='Whatthef:BAAALgAECggJCwAAAA==.',
Wi='Wildweasel:BAABLgAFFH8FAAIHAAIJgBqaLQCgAAAHAAIJgBqaLQCgAAABLgAFFAIJBwATAPAWAA==.Winterhide:BAABLgAECn8xAAIMAAkJoxnBIwB2AgAMAAkJoxnBIwB2AgAAAA==.',
Wo='Wolfe:BAAALgADCgIJAgAAAA==.',
Xa='Xallie:BAECLgAFFH8GAAIeAAMJaQgQcACpAAAeAAMJaQgQcACpAAAuAAQKf0AAAh4ACQl8GoUgAFECAB4ACQl8GoUgAFECAAAA.Xanvyr:BAABLgAECn8hAAIHAAkJXxk8PwAJAgAHAAkJXxk8PwAJAgAAAA==.Xaquillis:BAACLgAFFH8UAAMRAAQJlQy8BQAJAQARAAQJagu8BQAJAQAMAAMJuQ0ytQC8AAAuAAQKfyYAAwwACQkuGyc8AEcCAAwACAmYGyc8AEcCABEABAmwFr0VACsBAAAA.Xarthis:BAAALgAECgEJAQABLgAFFAQJFAARAJUMAA==.',
Xe='Xentrie:BAAALgADCgUJCgAAAA==.Xeyvara:BAABLgAECn8tAAIcAAkJoCTaAABCAwAcAAkJoCTaAABCAwAAAA==.',
Xg='Xg:BAAALgADCgUJBgABLgAECgYJJgAZALwfAA==.',
Xi='Xindra:BAAALgAECgkJCQAAAA==.',
Ya='Yamiyugi:BAAALgAECgEJAQAAAA==.Yatsui:BAAALgAECgQJBAAAAA==.',
Yo='Youngthug:BAAALgAECgIJAwAAAA==.',
Yu='Yutaa:BAAALgADCgYJBgAAAA==.',
Za='Zaden:BAAALgAECgYJBwAAAA==.Zangi:BAAALgAECgEJAwABLgAECgkJLAAEAL4hAA==.Zarihanna:BAABLgAECn84AAIFAAgJ0hd/BwCDAQAFAAgJ0hd/BwCDAQAAAA==.Zatannah:BAAALgADCgUJBQAAAA==.',
Ze='Zedryn:BAABLgAECn8nAAITAAkJew92RwDDAQATAAkJew92RwDDAQAAAA==.Zenshi:BAAALgAECgEJAgAAAA==.Zeperios:BAAALgAECgYJCgAAAA==.Zeril:BAABLgAECn8UAAMWAAgJjReLDACTAQAWAAgJjReLDACTAQATAAEJHgXrVwEoAAAAAA==.Zerq:BAAALgADCgkJCQAAAA==.Zestdruid:BAAALgAECggJEQAAAA==.Zestull:BAABLgAECn8lAAIPAAgJnCS2BgDOAgAPAAgJnCS2BgDOAgAAAA==.Zetsuboiki:BAAALgADCgcJCgAAAA==.Zetsudeath:BAAALgADCgYJBgAAAA==.Zetsudemon:BAAALgADCgMJAwAAAA==.',
Zh='Zhoel:BAAALgADCgEJAQAAAA==.',
Zi='Ziak:BAAALgAECgUJBQAAAA==.Zindeshal:BAAALgAECgYJCQAAAA==.',
Zo='Zorc:BAACLgAFFH8WAAIZAAUJhBcqGwBBAQAZAAUJhBcqGwBBAQAuAAQKfycAAhkACQmKIPsJAPQCABkACQmKIPsJAPQCAAAA.',
Zu='Zunji:BAAALgAECgEJBAAAAA==.',
Zy='Zyate:BAABLgAECn8xAAITAAkJTRJdRwDEAQATAAkJTRJdRwDEAQAAAA==.Zyrryn:BAABLgAECn8XAAIJAAgJwQOXEgDhAAAJAAgJwQOXEgDhAAAAAA==.',
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
