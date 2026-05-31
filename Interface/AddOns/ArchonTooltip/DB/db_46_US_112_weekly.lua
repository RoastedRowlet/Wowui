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

local lookup = {'Unknown-Unknown','Warrior-Fury','Druid-Balance','Druid-Restoration','Paladin-Retribution','Evoker-Devastation','Evoker-Augmentation','Warlock-Destruction','DeathKnight-Unholy','Warrior-Protection','Shaman-Restoration','Monk-Brewmaster','DeathKnight-Frost','Warrior-Arms','Hunter-BeastMastery','Warlock-Demonology','Hunter-Survival','Mage-Frost','Priest-Holy','Warlock-Affliction','Rogue-Subtlety','Paladin-Protection','Shaman-Elemental','Shaman-Enhancement','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Marksmanship','DeathKnight-Blood','Druid-Feral','Druid-Guardian','Paladin-Holy','Priest-Discipline','Priest-Shadow','Mage-Arcane','Rogue-Assassination','Evoker-Preservation','Monk-Windwalker','Monk-Mistweaver',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aagonyy:BAAALgAECgEJAgAAAA==.',
Ae='Aenninicus:BAAALgAECgEJAQAAAA==.Aernoth:BAAALgAECgUJDQAAAA==.',
Ak='Akaidia:BAAALgAECgYJBgABLgAECgYJCwABAAAAAA==.',
Al='Alderan:BAABLgAECn8lAAICAAcJIg6LPAA9AQACAAcJIg6LPAA9AQAAAA==.Aleinas:BAABLgAECn8kAAMDAAcJKxaULgBMAQADAAcJKxaULgBMAQAEAAQJQQgCjgCGAAAAAA==.Alektophobia:BAAALgAECggJEQAAAA==.Alendra:BAAALgAECgEJAQAAAA==.Alluisice:BAAALgAECgYJBgAAAA==.Allysaun:BAAALgAECgUJBgAAAA==.Alpharoach:BAAALgADCgYJBgAAAA==.Alzeinrich:BAAALgAECgYJEAAAAA==.',
Am='Amorina:BAABLgAECn8YAAIFAAgJjxOcYACWAQAFAAgJjxOcYACWAQAAAA==.',
An='Anda:BAAALgAECgMJAwAAAA==.Andarnn:BAAALgAECgEJAQAAAA==.Andracca:BAABLgAECn8cAAMGAAcJUQsnDQArAQAGAAcJUQsnDQArAQAHAAEJQAVIiwAkAAAAAA==.Andromeda:BAABLgAECn8VAAIEAAcJbwx1UgAyAQAEAAcJbwx1UgAyAQAAAA==.Aner:BAAALgAECgEJBgAAAA==.Angrygnome:BAACLgAFFH8HAAIIAAMJex6kBQAjAQAIAAMJex6kBQAjAQAuAAQKfx0AAggACQlVIJQBALQCAAgACQlVIJQBALQCAAAA.Angélique:BAAALgAFFAEJAQABLgAFFAUJFgAJANkiAA==.Antcension:BAAALgADCgUJBQAAAA==.Antemental:BAAALgAECgYJEAAAAA==.Anthigos:BAAALgAECgMJAwAAAA==.',
Ar='Arax:BAABLgAECn8dAAIKAAcJ7yGmDAAKAgAKAAcJ7yGmDAAKAgAAAA==.Arcada:BAAALgAECgUJBQABLgAECgUJBQABAAAAAA==.Arcamoon:BAAALgAECgIJAgABLgAECgUJBQABAAAAAA==.Arcashi:BAAALgADCgcJCgABLgAECgUJBQABAAAAAA==.Arianlion:BAAALgAECgEJAgAAAA==.Armistice:BAAALgAECgEJAgAAAA==.Arowenn:BAAALgADCgMJAwAAAA==.Arrokoth:BAAALgAECgEJAQAAAA==.Artana:BAAALgAECgIJAgAAAA==.',
As='Astolvik:BAAALgAECgQJBgAAAA==.',
At='Attachedplag:BAAALgAECgYJEAAAAA==.Atulwa:BAABLgAECn8hAAILAAkJdRYtJgAPAgALAAkJdRYtJgAPAgAAAA==.',
Au='Aurinox:BAAALgAECgUJEwAAAA==.Autodrive:BAAALgAECgUJCAAAAA==.',
Av='Avralea:BAABLgAECn8+AAIMAAgJ8BvqEQAUAgAMAAgJ8BvqEQAUAgAAAA==.',
Az='Azenthal:BAAALgAECgEJAQAAAA==.',
Ba='Bananahammik:BAAALgAECgYJDgAAAA==.Banzen:BAAALgAECgUJEgAAAA==.Basz:BAABLgAECn8rAAMJAAgJhhozOgAEAgAJAAgJhhozOgAEAgANAAMJDBDAHgCjAAAAAA==.',
Be='Beartank:BAAALgAECgQJBAABLgAFFAQJCAAOAJ4ZAA==.Beefburglar:BAAALgAECgYJBgAAAA==.Beginagain:BAAALgADCgcJCQAAAA==.Belfias:BAAALgAECgEJAgABLgAECgkJFgANAFMaAA==.Belgran:BAABLgAECn8WAAINAAkJUxrSAwA9AgANAAkJUxrSAwA9AgAAAA==.Belris:BAAALgAECgMJAwAAAA==.Berunma:BAABLgAECn8YAAIPAAgJ2BApaQBYAQAPAAgJ2BApaQBYAQAAAA==.',
Bh='Bhain:BAABLgAECn8hAAMQAAcJ5R3lSgDpAQAQAAcJ5R3lSgDpAQAIAAEJaA2FdAAwAAABLgAFFAQJDgAFADoaAA==.',
Bi='Bileshots:BAABLgAECn8UAAIRAAgJNRdJGQDGAQARAAgJNRdJGQDGAQAAAA==.Biowolf:BAACLgAFFH8VAAISAAQJmQf9YAAMAQASAAQJmQf9YAAMAQAuAAQKfywAAhIACQneFK48ABECABIACQneFK48ABECAAAA.Birdhunter:BAAALgAFFAEJAQAAAA==.Bishopixixix:BAAALgAECgYJCwAAAA==.Bits:BAABLgAECn8hAAIQAAgJSAeggAAtAQAQAAgJSAeggAAtAQAAAA==.',
Bj='Bjoren:BAABLgAECn8uAAITAAkJGySdAgBoAwATAAkJGySdAgBoAwAAAA==.',
Bl='Blackdread:BAAALgADCgYJBgAAAA==.Blasterjenny:BAAALgADCgkJDwAAAA==.Bloodcaptain:BAABLgAECn8cAAMIAAkJORfFBQD0AQAIAAkJZBbFBQD0AQAUAAYJshf6CAC3AQAAAA==.',
Bo='Bohma:BAAALgADCgEJAQAAAA==.Boopblast:BAAALgAECgQJCAAAAA==.Bootiebang:BAABLgAECn8VAAIVAAYJCQM+PAC3AAAVAAYJCQM+PAC3AAAAAA==.Bootycaall:BAAALgADCgkJGwAAAA==.Bootycall:BAAALgADCgkJCQAAAA==.Boroth:BAAALgADCgcJBwAAAA==.',
Br='Breetech:BAAALgAECgIJAgAAAA==.Brett:BAAALgAECgEJAQAAAA==.Breé:BAAALgAECgEJAQAAAA==.Brianx:BAAALgADCgIJAgAAAA==.Brklyn:BAAALgAFFAEJAQAAAA==.Brokki:BAAALgADCgEJAQAAAA==.',
Bu='Buckaroo:BAAALgAECgQJBQAAAA==.Bucknekkid:BAAALgAECgcJEgAAAA==.Buckwhild:BAABLgAECn8WAAITAAcJoyHBCwCTAgATAAcJoyHBCwCTAgAAAA==.Burrhus:BAAALgAECgQJBAAAAA==.',
Ca='Cagomei:BAAALgADCggJDgAAAA==.Caladbolg:BAABLgAECn82AAMWAAgJUSH8BACQAgAWAAgJUSH8BACQAgAFAAEJkAP5VwEnAAAAAA==.Camrillem:BAAALgAFFAEJAQAAAA==.Cannacola:BAABLgAECn8mAAMXAAYJvB/AJgCcAQAYAAYJ1BzoDQDeAQAXAAYJOh7AJgCcAQAAAA==.Carebearr:BAAALgAECgMJAwAAAA==.',
Ce='Cearius:BAAALgAECgYJCgABLgAFFAMJEAAQAGQlAA==.Cerdwin:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.Cesàrè:BAAALgAECgcJEgAAAA==.',
Ch='Chahra:BAABLgAECn8ZAAIZAAcJJA7CEQAWAQAZAAcJJA7CEQAWAQAAAA==.Chammie:BAAALgAECgYJBgAAAA==.Chamuki:BAACLgAFFH8GAAMaAAMJ4g/WGACYAAAaAAIJZhbWGACYAAAbAAEJ2wIwkAA0AAAuAAQKfxwAAxoACAn4HGoMAEACABoABwnBIGoMAEACABsABQm2DWurAK4AAAEuAAUUBAkPAAQAxx4A.Chaosbolt:BAAALgAECgEJAQAAAA==.Cheesecake:BAACLgAFFH8WAAMJAAUJ2SIzMQB0AQAJAAUJ2SIzMQB0AQANAAIJ3A8YFgCUAAAuAAQKfyYAAwkACQl+JcQCAK4DAAkACQl+JcQCAK4DAA0AAwn6GtMfAJkAAAAA.Cheesuspiece:BAAALgADCgIJAgAAAA==.Chrispbacon:BAAALgAECgMJBAAAAA==.Chuubak:BAAALgAECgkJBQAAAA==.',
Cl='Clangedin:BAABLgAECn8XAAICAAcJTQhzSgAFAQACAAcJTQhzSgAFAQAAAA==.',
Co='Cobalt:BAAALgADCgUJBQABLgAECgQJBAABAAAAAA==.Coreydruid:BAAALgAECgMJBwAAAA==.Coreypala:BAAALgAECgIJBAAAAA==.Coreysham:BAAALgAECgQJBQAAAA==.Corily:BAAALgADCgcJFwAAAA==.Corsten:BAABLgAECn8XAAIKAAcJww02IgAFAQAKAAcJww02IgAFAQAAAA==.Cosmictonic:BAAALgADCgYJBgAAAA==.',
Cr='Crabpack:BAAALgADCgIJAgAAAA==.Crayoneater:BAAALgAECgQJBAAAAA==.Crippleswagg:BAAALgAECgYJAQAAAA==.Croisades:BAAALgAECgQJCgAAAA==.Crosis:BAAALgADCgcJFwAAAA==.Crowmatic:BAABLgAECn8ZAAIJAAkJlR5nIwBkAgAJAAkJlR5nIwBkAgAAAA==.Crusadan:BAAALgADCgYJBgAAAA==.Cryo:BAAALgAECgEJAQAAAA==.',
Cu='Cucklizard:BAAALgAECgEJAQAAAA==.Cute:BAABLgAFFH8LAAICAAMJVyDUIQAUAQACAAMJVyDUIQAUAQAAAA==.',
['Cà']='Càhos:BAAALgADCgUJBQAAAA==.',
Da='Dakon:BAABLgAECn83AAMWAAkJThpuCAA1AgAWAAkJThpuCAA1AgAFAAIJcBi7DAF9AAAAAA==.Dalune:BAABLgAECn8nAAIXAAgJTAi8QAAUAQAXAAgJTAi8QAAUAQAAAA==.Daneaus:BAABLgAECn8rAAIEAAgJJyKXCgACAwAEAAgJJyKXCgACAwAAAA==.Daniellson:BAACLgAFFH8FAAIRAAMJrQwRHADeAAARAAMJrQwRHADeAAAuAAQKfxgABBwACAkoEesvALUBABwACAkoEesvALUBABEAAQk+EMZYADsAAA8AAQkAAFrcABcAAAEuAAUUBQkJAB0AOhEA.Daredevil:BAAALgAECgYJBwABLgAECggJFwAJALYcAA==.Darkchronos:BAAALgAECgEJAQAAAA==.Darkehawke:BAAALgAECgEJAQAAAA==.Darkscorp:BAAALgADCgkJDgAAAA==.Darkwolf:BAABLgAECn80AAMJAAkJ/RMiMgAiAgAJAAkJ/RMiMgAiAgAdAAgJXQaDLADcAAAAAA==.Darnuus:BAAALgAECgQJCwABLgAECggJHAAHABAJAA==.Datromandude:BAAALgAECgUJBQAAAA==.Dawnbringer:BAAALgADCgQJBAAAAA==.',
Db='Dblaster:BAAALgAECgUJCwAAAA==.',
De='Deathbydruid:BAABLgAECn8cAAMEAAkJqAI8kwB5AAAEAAgJBQI8kwB5AAADAAYJ1QADcwBJAAAAAA==.Deathnelf:BAABLgAECn8YAAMNAAgJAgvQEwASAQANAAgJAgvQEwASAQAJAAYJYQUH2gDCAAAAAA==.Deazraelle:BAABLgAECn8XAAIQAAcJ9Bc9RwC5AQAQAAcJ9Bc9RwC5AQAAAA==.Decimator:BAAALgADCggJHAAAAA==.Declan:BAAALgADCgUJBQAAAA==.Dedric:BAABLgAECn8nAAQeAAgJ8wrtHQDyAAAeAAgJGwjtHQDyAAADAAgJKgRxRgDVAAAfAAEJNRfbWABAAAAAAA==.Dellin:BAABLgAECn8pAAIDAAgJcBnzGADtAQADAAgJcBnzGADtAQAAAA==.Demeco:BAEALgAECgcJDgABLgAFFAgJGQAgAJwcAA==.Demonch:BAAALgAECgUJCAAAAA==.Demonweasel:BAAALgAECgYJBgABLgAECgcJEwABAAAAAA==.Depeche:BAABLgAECn8dAAIbAAYJ8BA9kADhAAAbAAYJ8BA9kADhAAAAAA==.Deralle:BAABLgAECn8cAAIHAAgJEAnJOwAaAQAHAAgJEAnJOwAaAQAAAA==.',
Di='Dil:BAAALgAECgIJAgAAAA==.Diminuendo:BAAALgAECgYJDwAAAA==.',
Do='Donalda:BAAALgAECgEJAQAAAA==.Dorillion:BAAALgAECgUJCQAAAA==.Dorozh:BAABLgAECn8eAAIIAAgJkBPvCQCJAQAIAAgJkBPvCQCJAQAAAA==.',
Dr='Draconx:BAAALgADCgYJBgAAAA==.Draghr:BAAALgAECgQJBAAAAA==.Dragonzmage:BAAALgAECgMJAwAAAA==.Dragskar:BAAALgADCgUJBQAAAA==.Drala:BAABLgAECn8gAAMhAAkJZhPOFAAVAgAhAAkJZhPOFAAVAgATAAEJ2w77ggAuAAAAAA==.Dreadmage:BAAALgADCgUJBQABLgADCgUJCQABAAAAAA==.Dreadpally:BAAALgADCgEJAQABLgADCgUJCQABAAAAAA==.Dreco:BAAALgADCgcJBwAAAA==.Driver:BAEALgAFFAIJBAABLgAFFAUJDwAQALYLAA==.Dryconias:BAACLgAFFH8IAAIFAAMJvBbgUgDnAAAFAAMJvBbgUgDnAAAuAAQKfy8AAwUACQmRG7ckAFkCAAUACQmRG7ckAFkCABYAAQmfCGdMACcAAAAA.Drèadpriest:BAABLgAECn8VAAQhAAUJwR0NIQChAQAhAAUJux0NIQChAQATAAUJ0hRLPQDnAAAiAAIJCRMGUQCJAAAAAA==.Drôgô:BAABLgAECn8VAAIPAAYJnhM7TgB+AQAPAAYJnhM7TgB+AQABLgAECggJCAABAAAAAA==.',
Du='Dunkelzhan:BAABLgAECn9BAAISAAkJEhssJQBxAgASAAkJEhssJQBxAgAAAA==.Duntack:BAAALgADCgEJAwAAAA==.',
Dy='Dyana:BAABLgAECn8eAAIPAAgJahQzQADKAQAPAAgJahQzQADKAQAAAA==.',
Dz='Dz:BAACLgAFFH8HAAIgAAQJJhi5GgAxAQAgAAQJJhi5GgAxAQAuAAQKf0AAAyAACQkoJk8AANsDACAACQkoJk8AANsDAAUABAktDhjeAMIAAAAA.',
['Dø']='Dømimømmÿ:BAAALgAECgUJCAAAAA==.',
Ed='Edgyname:BAAALgAECgYJEwAAAA==.Edgyvoid:BAAALgADCgYJDAAAAA==.Edlund:BAABLgAECn8iAAIGAAgJnA2OCQB7AQAGAAgJnA2OCQB7AQAAAA==.',
Ef='Effyinzpjake:BAAALgAECgYJDgAAAA==.',
Ei='Eianistic:BAAALgADCgEJAQAAAA==.',
El='Ellenee:BAAALgADCgMJAwAAAA==.Ellinor:BAAALgADCgcJJQAAAA==.Elvy:BAABLgAECn8vAAIDAAkJVxgcFwD+AQADAAkJVxgcFwD+AQAAAA==.',
En='Enngin:BAAALgAFFAMJAwAAAA==.Enroks:BAAALgAECgUJBQAAAA==.',
Er='Erebus:BAAALgAECgYJDAAAAA==.Erythra:BAAALgAECgQJBAAAAA==.',
Ev='Evildefiant:BAAALgAECgEJAQAAAA==.',
Ex='Exsalsior:BAAALgADCgYJBgAAAA==.',
Ey='Eyedoc:BAAALgADCgQJBAAAAA==.',
Fa='Fabulousness:BAABLgAECn8jAAITAAgJ+R8NCgCyAgATAAgJ+R8NCgCyAgAAAA==.',
Fe='Fearliz:BAAALgADCgEJAQAAAA==.',
Fi='Fifefrost:BAAALgAECgQJBAAAAA==.Fishingsucks:BAAALgAECgcJCgAAAA==.',
Fl='Flexi:BAAALgADCgEJAQAAAA==.Flitred:BAAALgAECggJDwAAAA==.Flock:BAAALgAECgcJCQAAAA==.',
Fo='Foxx:BAAALgAECgUJDQAAAA==.',
Fr='Framboise:BAABLgAECn8ZAAICAAYJUQcaYAAwAQACAAYJUQcaYAAwAQAAAA==.Frostybolt:BAAALgAECgUJBwAAAA==.',
Fu='Furryriver:BAAALgAECgYJDwAAAA==.',
['Fø']='Føxx:BAAALgAECgEJAQAAAA==.',
Ga='Galadhras:BAAALgADCgYJFAAAAA==.Galdryn:BAAALgADCgIJAQAAAA==.Galianna:BAABLgAECn8WAAITAAgJOhKtHADIAQATAAgJOhKtHADIAQAAAA==.Gamboslice:BAAALgAECgIJAgAAAA==.Garkevon:BAAALgADCgMJAwAAAA==.',
Ge='Gemeni:BAAALgAECgEJAQAAAA==.Gevul:BAABLgAECn9HAAMQAAkJyhfjIwBDAgAQAAkJZhfjIwBDAgAIAAQJ+Q1yRgCcAAAAAA==.',
Gh='Ghostess:BAAALgADCgkJAQAAAA==.Ghrank:BAABLgAECn8VAAQIAAcJvgj3HQCkAAAQAAcJUQdKlAAJAQAUAAYJHwifGADYAAAIAAYJ8Qf3HQCkAAAAAA==.',
Gi='Gilliruni:BAAALgADCgUJBQAAAA==.Gitpull:BAAALgAECggJDQAAAA==.',
Gl='Glimley:BAAALgADCgMJAwAAAA==.',
Gn='Gnimsh:BAAALgAECgEJAQAAAA==.Gnorst:BAAALgADCgkJCgAAAA==.',
Go='Goreolio:BAAALgADCgkJDwABLgAECgYJEQABAAAAAA==.',
Gr='Grandmatank:BAAALgADCgkJCQAAAA==.Grasshopaa:BAAALgADCgYJCQAAAA==.Grassy:BAAALgADCgkJCQAAAA==.Greengoatlin:BAAALgADCgcJBwAAAA==.Gremlock:BAAALgAECgEJAQAAAA==.Gremz:BAABLgAECn8mAAIZAAkJCQp/DgBLAQAZAAkJCQp/DgBLAQAAAA==.Grozny:BAAALgADCgYJBgAAAA==.Grày:BAABLgAECn8wAAIJAAkJXx08HACKAgAJAAkJXx08HACKAgAAAA==.',
Gu='Gumboslice:BAACLgAFFH8KAAIEAAQJ7RF6JwAMAQAEAAQJ7RF6JwAMAQAuAAQKfx8AAgQACQnSHRQKAAkDAAQACQnSHRQKAAkDAAAA.Gusgus:BAABLgAECn8WAAISAAgJcgVCqgAPAQASAAgJcgVCqgAPAQAAAA==.',
['Gä']='Gändälf:BAABLgAECn8XAAIjAAgJvxX1AwCyAQAjAAgJvxX1AwCyAQAAAA==.',
Ha='Habanero:BAABLgAECn8pAAMLAAgJKg2LTABhAQALAAgJKg2LTABhAQAXAAQJUxilRQABAQAAAA==.Hachedev:BAAALgAECgMJCAAAAA==.Hadtopandadk:BAAALgAECgQJBQAAAA==.Hallia:BAACLgAFFH8GAAIEAAMJ9BEuNwDAAAAEAAMJ9BEuNwDAAAAuAAQKfzUAAgQACQkBF9MYAGwCAAQACQkBF9MYAGwCAAAA.Hark:BAAALgADCgcJIQAAAA==.Havvocchi:BAAALgAECgEJAQAAAA==.Hawgwild:BAABLgAECn8WAAIJAAUJyBL5tAD3AAAJAAUJyBL5tAD3AAAAAA==.',
He='Headdinks:BAAALgADCgcJDAAAAA==.Healcap:BAAALgADCgQJBAAAAA==.Healvisprsly:BAABLgAECn8WAAMEAAcJeBZEOACjAQAEAAYJgRhEOACjAQADAAYJ9BglIgCeAQAAAA==.Heisenberg:BAAALgADCgMJAwABLgAECgMJBwABAAAAAA==.Helena:BAABLgAECn9AAAMFAAkJWSMSBwAiAwAFAAkJViMSBwAiAwAWAAkJUB5wBAChAgAAAA==.Heliarc:BAAALgADCgcJJQAAAA==.Hermès:BAAALgAECgUJBgABLgAFFAUJFgAJANkiAA==.',
Hi='Highfive:BAAALgAECgUJCwAAAA==.',
Ho='Holybeech:BAAALgAECgQJBAAAAA==.Honestly:BAAALgAECgYJDwAAAA==.Honkytonkman:BAAALgADCgQJBAAAAA==.Hover:BAAALgAECgYJEQAAAA==.',
Ih='Ihmoen:BAAALgADCgYJBgAAAA==.',
Il='Illuminate:BAAALgADCgQJBAAAAA==.Illustria:BAAALgADCgcJHAAAAA==.Illustriâ:BAAALgADCgYJCQABLgADCgcJHAABAAAAAA==.',
Im='Imprison:BAAALgAECgYJBgABLgAECgcJFQASANIXAA==.',
In='Insidious:BAABLgAECn8fAAIdAAkJFRojDQAeAgAdAAkJFRojDQAeAgAAAA==.Invoke:BAAALgADCgEJAQAAAA==.',
Ir='Irs:BAAALgAECgUJBwAAAA==.',
It='Itchyfeet:BAAALgAECgUJCAABLgAFFAQJEgASAL0hAA==.Itchymage:BAACLgAFFH8SAAISAAQJvSHNLwB/AQASAAQJvSHNLwB/AQAuAAQKfyQAAhIACQnIIzMdAAEDABIACQnIIzMdAAEDAAAA.',
Ja='Jacckiemoon:BAAALgAECgMJAwABLgAECgcJFgAEAHgWAA==.Jadehunterr:BAAALgAECgMJBAAAAA==.Jaesn:BAAALgADCgYJBgAAAA==.',
Je='Jenae:BAAALgAECgEJAQAAAA==.Jenövha:BAAALgADCgkJFwAAAA==.Jezebelle:BAAALgAECgUJBQAAAA==.',
Ji='Jigs:BAABLgAECn86AAIPAAgJ7BUTPQDVAQAPAAgJ7BUTPQDVAQAAAA==.Jiräiya:BAAALgADCgYJBgAAAA==.',
Jo='Johastrasz:BAAALgADCggJCAAAAA==.',
Ju='Junsing:BAAALgADCgEJAQABLgAECggJHAAHABAJAA==.',
['Jå']='Jåfar:BAAALgADCgEJAgAAAA==.',
Ka='Kabøchi:BAAALgAECgUJBQAAAA==.Kaladriel:BAAALgADCgEJAQAAAA==.Kaldrick:BAAALgAECgkJEAAAAA==.Kamstareater:BAABLgAECn8lAAIbAAgJWBNRSgCPAQAbAAgJWBNRSgCPAQAAAA==.Kanakas:BAAALgAECggJEgAAAA==.Kanaloa:BAABLgAECn8dAAISAAgJ6QmGjQBBAQASAAgJ6QmGjQBBAQAAAA==.Kayler:BAAALgAECgYJBgABLgAECgYJCwABAAAAAA==.',
Ke='Kegerator:BAAALgAECgMJBAAAAA==.Keirin:BAAALgAECggJEgAAAA==.Keldica:BAAALgAECgIJAgAAAA==.Kelysa:BAAALgAECggJDwAAAA==.Kena:BAAALgADCgUJBQAAAA==.Kenshan:BAAALgAECgMJAwAAAA==.Kevinbox:BAAALgAECgYJEAAAAA==.Kevinslayer:BAAALgAECgUJDAAAAA==.Keynaridan:BAABLgAECn8VAAIbAAgJYRHJUgB2AQAbAAgJYRHJUgB2AQAAAA==.Keyss:BAAALgADCgIJAgAAAA==.',
Kg='Kglizard:BAAALgAECgUJCAAAAA==.',
Kh='Khalinor:BAABLgAECn8eAAIgAAgJLhKRJgC/AQAgAAgJLhKRJgC/AQAAAA==.Khardun:BAAALgAECgEJAQAAAA==.Khotuhn:BAAALgADCgkJGAAAAA==.',
Ki='Kickazdin:BAABLgAECn8YAAMgAAkJoh0XDQCqAgAgAAgJgB4XDQCqAgAFAAIJBQrxIwFpAAAAAA==.Kiryie:BAABLgAECn8ZAAIPAAcJvA3KZwBbAQAPAAcJvA3KZwBbAQAAAA==.Kisäme:BAAALgAECggJCgAAAA==.',
Kl='Klad:BAAALgAECgEJAQAAAA==.Kluma:BAAALgAECgEJAQAAAA==.',
Kn='Knok:BAAALgAECggJCAAAAA==.',
Ko='Kobu:BAAALgADCgUJBgAAAA==.Konran:BAAALgADCgEJAQAAAA==.',
Kr='Kraigen:BAABLgAECn8kAAIaAAgJeB05DQAyAgAaAAgJeB05DQAyAgAAAA==.Krinack:BAABLgAECn8jAAIVAAkJlBGfEwDvAQAVAAkJlBGfEwDvAQAAAA==.Krixiz:BAAALgAECgYJCgAAAA==.',
Ks='Kshamify:BAAALgAFFAIJBAAAAA==.',
Ku='Kurindrixx:BAAALgADCgIJAgAAAA==.Kurtakum:BAAALgADCgMJAwAAAA==.Kutiel:BAAALgAECgYJEQAAAA==.',
Kw='Kwarify:BAAALgADCgEJAQAAAA==.',
Ky='Kynasmira:BAAALgADCgcJHQAAAA==.Kyrsh:BAAALgADCgcJEAAAAA==.',
La='Ladrona:BAABLgAECn8ZAAIkAAkJ+B2+AQDOAgAkAAkJ+B2+AQDOAgAAAA==.Lailyre:BAAALgAECgYJCwAAAA==.Lassan:BAAALgAECgYJCQAAAA==.Later:BAAALgAECggJDAAAAA==.Latimir:BAAALgAECgIJAgAAAA==.Laur:BAAALgADCgYJBgAAAA==.Lavendeer:BAABLgAECn8jAAIDAAkJFhPPGgDaAQADAAkJFhPPGgDaAQAAAA==.Laylana:BAAALgADCgIJAgABLgADCgUJCQABAAAAAA==.Lazyeye:BAAALgADCgUJBAABLgAECgcJDQABAAAAAA==.',
Lb='Lb:BAAALgADCgUJBgABLgAECgkJEwABAAAAAA==.',
Le='Legume:BAAALgADCgcJCAABLgAECgUJDQABAAAAAA==.Legzanot:BAACLgAFFH8RAAIXAAQJcgo3JwDdAAAXAAQJcgo3JwDdAAAuAAQKfygAAhcACQkyFiQdACgCABcACQkyFiQdACgCAAAA.Leonceault:BAAALgAECgEJAQAAAA==.',
Li='Lifebringa:BAABLgAECn8pAAMTAAcJ/x1UDwBbAgATAAcJ/x1UDwBbAgAiAAYJIBmlJwBwAQAAAA==.Lightningfox:BAABLgAECn8jAAMFAAgJwhcRRwDZAQAFAAgJwhcRRwDZAQAgAAIJug6TbABmAAAAAA==.Lightsfallen:BAAALgAECggJDgAAAA==.Lileth:BAAALgAECgYJBAAAAA==.Limzzmagus:BAAALgAECgMJBgAAAA==.Lithia:BAABLgAECn8ZAAIJAAcJQw/EggBJAQAJAAcJQw/EggBJAQAAAA==.Littlemo:BAAALgAECgYJDwAAAA==.',
Lo='Loggs:BAAALgAFFAEJAQAAAA==.Lohnar:BAAALgAECgYJDwAAAA==.Lornah:BAAALgADCgQJBAAAAA==.',
Lu='Lucidslock:BAAALgADCgIJAgAAAA==.Lucielbaal:BAABLgAECn8rAAIQAAgJSR/tFwCIAgAQAAgJSR/tFwCIAgAAAA==.Luciferus:BAAALgAECgQJBAABLgAECggJLQARACIPAA==.Luckystop:BAAALgAECgYJDgAAAA==.Lumenir:BAAALgAECgEJAQAAAA==.Lunareth:BAAALgADCgUJBQAAAA==.Luraris:BAAALgAECgEJAQAAAA==.',
Ly='Lyrska:BAABLgAECn8oAAIRAAgJqRCHGgC7AQARAAgJqRCHGgC7AQAAAA==.Lytearrow:BAABLgAECn8iAAIPAAgJEg/YVwCEAQAPAAgJEg/YVwCEAQAAAA==.',
['Lé']='Léaf:BAAALgAECgMJAwAAAA==.',
Ma='Mahrylee:BAAALgAECgcJEAAAAA==.Maiya:BAAALgADCgcJEAAAAA==.Majutsu:BAAALgADCgEJAQABLgADCgcJDgABAAAAAA==.Malbrax:BAABLgAECn8YAAIQAAgJQhBfVwCLAQAQAAgJQhBfVwCLAQAAAA==.Maleficents:BAABLgAECn8pAAIDAAcJTBGOLgBMAQADAAcJTBGOLgBMAQAAAA==.Malurius:BAABLgAECn8bAAMOAAkJshRWDgDvAQAOAAkJsRJWDgDvAQACAAYJ4AowXQDEAAAAAA==.Malware:BAAALgAECgYJEQAAAA==.Manana:BAAALgADCgEJAQAAAA==.Manbearpally:BAAALgAECgQJBAAAAA==.Manikfury:BAABLgAECn8iAAMeAAgJwBs9CAAqAgAeAAgJwBs9CAAqAgAEAAYJYx4IKgDyAQAAAA==.Maniksmage:BAAALgADCgUJDAABLgAECggJIgAeAMAbAA==.Mannypack:BAABLgAECn8dAAQDAAgJixyqEgArAgADAAgJixyqEgArAgAEAAQJkAwUegC3AAAfAAEJOxNQXQA3AAAAAA==.Maranelli:BAAALgADCgYJBgAAAA==.Maseles:BAAALgAECgUJBgABLgAECgUJCQABAAAAAA==.Maxiticon:BAAALgAECgYJDAAAAA==.',
Mc='Mcdawg:BAAALgADCgYJCgAAAA==.Mcleary:BAAALgAECgUJBgAAAA==.',
Me='Melinashala:BAABLgAECn8mAAIQAAgJaQQzlgAGAQAQAAgJaQQzlgAGAQAAAA==.Mending:BAAALgAECgUJBQAAAA==.Meowinator:BAAALgAECgYJDQAAAA==.Mephizto:BAAALgAECgYJCQAAAA==.Metatrøn:BAAALgAECgIJAgAAAA==.Metide:BAAALgAECgQJBAAAAA==.',
Mi='Miala:BAAALgAECgEJAQAAAA==.Mierna:BAAALgAECggJDwAAAA==.Miler:BAAALgAECgQJBgAAAA==.Millylittle:BAAALgADCgUJBQAAAA==.Minisor:BAAALgAECgUJBQAAAA==.Misanth:BAAALgAECgYJDgAAAA==.Mistdruid:BAAALgAECgIJAwABLgAECgIJBgABAAAAAA==.',
Mo='Moemo:BAABLgAECn8gAAIEAAkJQh+xCQAPAwAEAAkJQh+xCQAPAwAAAA==.Mogryn:BAAALgAECggJEgAAAA==.Moistymists:BAAALgAECgYJCQAAAA==.Moll:BAAALgADCgEJAQAAAA==.Mommybree:BAAALgAECgYJEQAAAA==.Monksterz:BAABLgAECn8uAAIMAAkJzyA5BQDgAgAMAAkJzyA5BQDgAgAAAA==.Monoxidê:BAAALgAECgEJAQAAAA==.Moonwarriorx:BAAALgAECggJDAAAAA==.Morsecode:BAABLgAECn8ZAAIIAAcJFRRbCwBtAQAIAAcJFRRbCwBtAQABLgABCgIJAgABAAAAAA==.Morthok:BAABLgAECn8qAAIQAAgJCBicNQD2AQAQAAgJCBicNQD2AQAAAA==.Mortischa:BAAALgADCggJCAAAAA==.Mosh:BAABLgAECn8bAAIMAAkJDhTLFwDYAQAMAAkJDhTLFwDYAQAAAA==.',
Mu='Muchuchu:BAAALgAECgQJDgABLgAECgIJAgABAAAAAA==.Muldern:BAAALgAECgEJAQAAAA==.Munkee:BAAALgAECgYJEQAAAA==.Murdinbronze:BAAALgADCgUJCAAAAA==.Mustachekick:BAAALgADCgUJBwAAAA==.Musyl:BAAALgADCgEJAQABLgAECgYJEQABAAAAAA==.',
['Mã']='Mãf:BAABLgAECn8iAAMLAAcJmRKYXwAfAQALAAYJbA+YXwAfAQAXAAEJtxwjgABTAAAAAA==.',
['Mí']='Místwalker:BAAALgAECgIJBgAAAA==.',
Na='Nackthyr:BAACLgAFFH8WAAIGAAQJCiahAADAAQAGAAQJCiahAADAAQAuAAQKfz0AAgYACQmxJjAAAH8DAAYACQmxJjAAAH8DAAAA.Nafir:BAAALgADCgYJFwAAAA==.Nakky:BAAALgAECgEJAQAAAA==.Narlin:BAAALgAECgYJCQAAAA==.Nasta:BAAALgAFFAIJAgAAAA==.Natureboi:BAAALgADCgQJBAABLgADCgYJDAABAAAAAA==.Nazareths:BAAALgAECgQJCwAAAA==.Nazgor:BAAALgAECgMJAwAAAA==.',
Ne='Neckromancy:BAAALgADCgcJBwAAAA==.Necrosius:BAAALgAECgYJDgAAAA==.Neonarc:BAEALgADCgYJFwAAAA==.Neshi:BAAALgAECgMJBQAAAA==.Neuman:BAAALgADCgEJAQAAAA==.',
Ni='Nibblemah:BAAALgAECgUJBQAAAA==.Nightsbane:BAAALgADCgcJEAAAAA==.Nivdk:BAAALgADCgYJBgABLgAECgYJEQABAAAAAA==.Nivora:BAAALgAECgYJEQAAAA==.',
No='Notsure:BAAALgAECgkJDQAAAA==.',
Ny='Nyxstalia:BAAALgAECgUJDAAAAA==.Nyyx:BAABLgAECn8dAAIbAAgJqgUGkADhAAAbAAgJqgUGkADhAAAAAA==.',
['Ná']='Nácl:BAAALgAECgcJBwABLgAFFAQJFgAGAAomAA==.',
Ob='Obscyra:BAAALgAECgMJAwAAAA==.',
Ol='Olmek:BAACLgAFFH8XAAICAAYJTBcvCgCSAQACAAYJTBcvCgCSAQAuAAQKfxwAAgIABwkrJtINAH8CAAIABwkrJtINAH8CAAAA.',
Op='Opalana:BAAALgADCgIJAwAAAA==.Oprahwndfury:BAAALgAECgQJCAABLgAECgcJFgAEAHgWAA==.',
Or='Orasaya:BAAALgADCgYJBgAAAA==.Orphee:BAAALgADCgcJBwAAAA==.Orzanis:BAAALgADCgcJDgAAAA==.',
Pa='Paige:BAAALgADCgcJDgAAAA==.Palasades:BAAALgADCgUJBQAAAA==.Pallymarc:BAAALgADCgYJBgAAAA==.Pallytune:BAACLgAFFH8LAAIgAAMJDAxNKwC4AAAgAAMJDAxNKwC4AAAuAAQKfxsAAiAACQnxDoYhAOEBACAACQnxDoYhAOEBAAAA.Pandalorian:BAAALgAECgYJEAAAAA==.Pandamajack:BAAALgAECggJDQAAAA==.',
Ph='Philandre:BAABLgAECn8VAAIFAAgJZQ7WeABiAQAFAAgJZQ7WeABiAQAAAA==.',
Pi='Picoso:BAABLgAECn8gAAISAAgJLQuEggBXAQASAAgJLQuEggBXAQAAAA==.Piianca:BAAALgAECgMJBAAAAA==.Piianna:BAABLgAECn8ZAAITAAcJoBswGAD1AQATAAcJoBswGAD1AQAAAA==.Pirko:BAAALgADCggJCwAAAA==.',
Po='Pocketheal:BAAALgADCgkJEAAAAA==.',
Pt='Pteradactyl:BAAALgAECgEJAQAAAA==.',
Pu='Punch:BAAALgAECgEJAgAAAA==.Purplerain:BAAALgAECgMJBAAAAA==.Putrigord:BAAALgAECgQJCwAAAA==.',
Py='Pylarthius:BAAALgADCgcJBwAAAA==.',
Qi='Qik:BAAALgADCgcJBwAAAA==.Qikkaw:BAABLgAECn8gAAMLAAgJaQ+vSgBoAQALAAgJaQ+vSgBoAQAXAAUJtwnKYgCgAAAAAA==.Qitetsu:BAAALgAECgUJBgAAAA==.',
Qu='Quantos:BAABLgAECn8oAAIfAAgJEhIQIgAYAQAfAAgJEhIQIgAYAQAAAA==.Ququmatz:BAAALgADCgMJAwAAAA==.',
Ra='Raatha:BAABLgAECn8fAAIFAAgJTxg+PAD7AQAFAAgJTxg+PAD7AQAAAA==.Raeyla:BAAALgAECgEJAQAAAA==.Raganar:BAABLgAECn8nAAIWAAgJIxOsEgCDAQAWAAgJIxOsEgCDAQAAAA==.Ranlerodis:BAAALgADCgMJAwAAAA==.Rayjean:BAAALgADCgYJGAABLgADCgcJBwABAAAAAA==.',
Re='Redneckboots:BAAALgADCgEJAQAAAA==.Relmax:BAABLgAECn8eAAIKAAgJtQisIQAKAQAKAAgJtQisIQAKAQAAAA==.Rendeminae:BAAALgADCgcJBwAAAA==.Renri:BAABLgAECn8ZAAIVAAcJphSOHQCQAQAVAAcJphSOHQCQAQAAAA==.Repose:BAAALgAECgIJAwAAAA==.Revick:BAAALgAECgUJCAAAAA==.Revil:BAAALgADCgIJAgAAAA==.',
Rh='Rhaenýs:BAAALgADCgcJDQAAAA==.Rhonwynn:BAABLgAECn8gAAILAAgJ1xmvGgBbAgALAAgJ1xmvGgBbAgAAAA==.',
Ri='Rikershipdwn:BAABLgAECn8YAAIPAAgJGhSyRgC1AQAPAAgJGhSyRgC1AQAAAA==.Rikersline:BAAALgADCgkJCQAAAA==.Rimish:BAAALgAECggJEAABLgAECgkJJAAkALgaAA==.Rimrave:BAABLgAECn8pAAQOAAgJVh0QCgAwAgAOAAgJpxsQCgAwAgACAAYJIxscNQDVAQAKAAYJiB3vFgB0AQAAAA==.Ripavicii:BAAALgAECgEJAQAAAA==.Ritobeans:BAAALgADCgcJJQAAAA==.Rivik:BAAALgAECgQJAwAAAA==.',
Ro='Robbstark:BAAALgAECgYJDAAAAA==.Robertkenway:BAABLgAECn8tAAMRAAgJIg+jHACpAQARAAgJIg+jHACpAQAPAAEJAADX1AAwAAAAAA==.Roguebot:BAAALgADCgkJEgAAAA==.Rohdaric:BAABLgAECn8ZAAIRAAYJUxTNFgBdAQARAAYJUxTNFgBdAQAAAA==.Rokte:BAABLgAECn8ZAAIUAAcJ9RCQDQBfAQAUAAcJ9RCQDQBfAQAAAA==.Roo:BAAALgAECgEJAwAAAA==.Rook:BAABLgAECn8gAAQQAAgJ3iJ8EQC0AgAQAAgJxCF8EQC0AgAIAAMJmBmAIQCJAAAUAAEJAAADPwAAAAAAAA==.Rosekenway:BAABLgAECn8eAAMEAAgJTwo+UQA3AQAEAAgJTwo+UQA3AQADAAQJzQgAYAB5AAABLgAECggJLQARACIPAA==.',
Rr='Rratt:BAAALgAECgQJBgAAAA==.',
Ru='Rubimoon:BAAALgAECgUJBQAAAA==.Rumí:BAAALgAECgcJBwAAAA==.Running:BAAALgAECgIJAgAAAA==.',
Sa='Saammiee:BAAALgAECgIJAgAAAA==.Sabiha:BAABLgAECn8UAAMPAAYJaA+qZQA2AQAPAAYJaA+qZQA2AQAcAAEJwQPplAAlAAAAAA==.Safewaybag:BAAALgADCgQJBAAAAA==.Saintb:BAAALgADCggJCAAAAA==.Saintotem:BAABLgAECn8kAAIXAAgJNBHdKgCDAQAXAAgJNBHdKgCDAQAAAA==.Samartyr:BAAALgAECgUJCAAAAA==.Samison:BAAALgAECgYJBgAAAA==.Sammiiee:BAAALgADCgQJBAABLgAECgIJAgABAAAAAA==.Sandii:BAAALgADCgcJBwAAAA==.Sangwynaris:BAAALgAECgcJCAAAAA==.Saphiiraa:BAABLgAECn8lAAIlAAgJaRGlEACtAQAlAAgJaRGlEACtAQAAAA==.Sayahealer:BAAALgADCgcJDgAAAA==.',
Sc='Scorpmage:BAABLgAECn8hAAISAAgJ1RbYSwDgAQASAAgJ1RbYSwDgAQAAAA==.Scramms:BAAALgADCgcJDQAAAA==.Scrams:BAABLgAECn8VAAIcAAcJpwxvEwARAQAcAAcJpwxvEwARAQAAAA==.',
Se='Sedrick:BAABLgAECn82AAMgAAkJRSClCgDNAgAgAAgJMiGlCgDNAgAFAAYJzhXzhgBHAQAAAA==.Sekendipity:BAAALgADCgEJAQABLgAECgcJDQABAAAAAA==.Sekhmett:BAAALgADCgMJAwAAAA==.Sekndestroy:BAAALgADCgYJCQABLgAECgcJDQABAAAAAA==.Sektacular:BAAALgADCgQJBAABLgAECgcJDQABAAAAAA==.Sekzen:BAAALgAECgcJDQAAAA==.Semiazas:BAABLgAECn8uAAQUAAkJ+Q1uCQCrAQAUAAkJ+Q1uCQCrAQAQAAUJ2QmotwDpAAAIAAEJAAD7egAnAAAAAA==.Semiazes:BAAALgADCgYJBgAAAA==.Senessa:BAAALgADCgIJAgAAAA==.Sensy:BAAALgAECgQJCQAAAA==.Serwonton:BAAALgADCgUJBQAAAA==.Seumas:BAAALgADCgMJAwAAAA==.',
Sh='Shadrock:BAAALgADCgYJBgAAAA==.Shattered:BAAALgAECgkJEQAAAA==.Shayrisa:BAABLgAECn81AAMLAAkJTBJjNgC8AQALAAkJTBJjNgC8AQAXAAcJ4w7DQAAUAQAAAA==.Shazool:BAABLgAECn8ZAAMLAAcJ4CASFgCBAgALAAcJ4CASFgCBAgAYAAIJkQu1KgBoAAABLgAFFAMJBgAEAPQRAA==.Sheep:BAABLgAECn8VAAISAAcJ0hd3aQCQAQASAAcJ0hd3aQCQAQAAAA==.Shifterz:BAAALgAECgYJDgAAAA==.Shrieke:BAAALgAECgQJBAAAAA==.Shrubbery:BAABLgAECn8eAAIfAAgJmBEAGQBjAQAfAAgJmBEAGQBjAQAAAA==.Shxdow:BAAALgAECgQJBAAAAA==.',
Si='Sind:BAAALgAECgMJBAABLgAECgkJKgAfAAMVAA==.Sindella:BAAALgAECgMJAwABLgAECgkJKgAfAAMVAA==.Sinna:BAAALgADCgUJCQAAAA==.Sinthorne:BAABLgAECn8qAAMfAAkJAxUHDwDUAQAfAAgJcxcHDwDUAQAeAAMJ8AWgMwBlAAAAAA==.',
Sk='Skedaddle:BAAALgAECgUJCQABLgAECggJNgASALwkAA==.Skithíryx:BAAALgAECgYJCQABLgAECgYJCwABAAAAAA==.',
Sl='Slashbndcoot:BAAALgAFFAMJAwAAAA==.Slashgquit:BAACLgAFFH8PAAIdAAQJlB4RDwBSAQAdAAQJlB4RDwBSAQAuAAQKfzMAAh0ACQmIJPwCAAoDAB0ACQmIJPwCAAoDAAAA.Slumbermist:BAABLgAECn81AAMmAAkJxhFJGgDGAQAmAAkJxhFJGgDGAQAnAAcJcREWRgAfAQABLgABCgIJAgABAAAAAA==.',
So='Solaire:BAABLgAECn8hAAMWAAcJWRzQDgC7AQAWAAcJWRzQDgC7AQAgAAUJqRCFSQD/AAABLgAFFAQJCQAmAMQiAA==.Soras:BAAALgADCgYJGwAAAA==.Sourjack:BAAALgAECgQJBQAAAA==.',
St='Steph:BAAALgAECgUJBQAAAA==.',
Su='Sunareas:BAAALgADCgIJAgAAAA==.',
Sy='Synthetic:BAABLgAECn8cAAIIAAgJzBWwBwC6AQAIAAgJzBWwBwC6AQAAAA==.Syrebriel:BAAALgADCgEJAgABLgAECgYJEQABAAAAAA==.',
Sz='Szasstaam:BAABLgAECn8gAAMjAAgJWAfoBwAJAQAjAAgJWAfoBwAJAQASAAMJLwKFKwFFAAAAAA==.',
['Sé']='Sénåtor:BAAALgADCgYJCAABLgAECgkJKgAFAFATAA==.Séékér:BAAALgADCgcJFQAAAA==.',
Ta='Talanith:BAAALgADCggJEAAAAA==.Tarayk:BAAALgADCgYJBgABLgADCgcJBwABAAAAAA==.Taxal:BAAALgADCgYJBwAAAA==.Taxlock:BAABLgAECn8aAAIQAAcJ9wl9jQAWAQAQAAcJ9wl9jQAWAQAAAA==.',
Tb='Tbagjones:BAAALgAECgQJBAAAAA==.',
Te='Tecsaran:BAABLgAECn8UAAISAAYJ1B/ebgD2AQASAAYJ1B/ebgD2AQAAAA==.Tekis:BAAALgADCgEJAQAAAA==.Terania:BAAALgADCgIJAgAAAA==.',
Th='Thalira:BAABLgAECn8cAAQlAAgJvwhMHAAIAQAlAAcJ/AZMHAAIAQAHAAcJTwIaZwB7AAAGAAQJrQGENQBpAAAAAA==.',
Ti='Tibbz:BAAALgADCgIJAgAAAA==.Tiger:BAACLgAFFH84AAMeAAkJECUBAACwAwAeAAkJECUBAACwAwAEAAMJxhYuFwCoAAAuAAQKfyoAAx4ACQnqJgUAABYEAB4ACQnqJgUAABYEAAQAAQm1C4TEAD8AAAAA.Tinnea:BAAALgAECgUJDgAAAA==.Titanosaurus:BAAALgAECgYJDwAAAA==.Tizzly:BAABLgAECn8rAAISAAkJzQ54YgChAQASAAkJzQ54YgChAQAAAA==.',
To='Torhilda:BAAALgAECgYJBgAAAA==.Torridwells:BAABLgAECn8ZAAIPAAcJJQ58ZQBgAQAPAAcJJQ58ZQBgAQAAAA==.',
Tr='Trad:BAAALgADCgYJBgAAAA==.Troag:BAABLgAECn8cAAILAAgJsxsZFwB4AgALAAgJsxsZFwB4AgAAAA==.Troagstar:BAABLgAECn8iAAIXAAgJixpSGAAJAgAXAAgJixpSGAAJAgAAAA==.',
Ts='Tsaesci:BAAALgADCgQJBgAAAA==.Tsynn:BAAALgADCgYJFAAAAA==.',
Ty='Tyraana:BAABLgAECn85AAMaAAkJbh9PBQDSAgAaAAkJbh9PBQDSAgAbAAgJ3RSiRQCeAQAAAA==.Tyrinwar:BAAALgADCgYJDAAAAA==.Tyrmog:BAABLgAECn8XAAIJAAcJVAgGqgAHAQAJAAcJVAgGqgAHAQAAAA==.Tytus:BAAALgADCgIJAgAAAA==.',
Un='Unique:BAAALgAECgEJAQABLgAFFAQJEwACAJ4lAA==.',
Us='Ushas:BAABLgAECn8wAAMTAAkJxBfMGADvAQATAAkJxBfMGADvAQAhAAQJqQVpUQCKAAAAAA==.',
Va='Vali:BAABLgAECn8qAAIcAAgJ0x/uAwBvAgAcAAgJ0x/uAwBvAgAAAA==.Valindrea:BAAALgAECgYJDwAAAA==.Vasrael:BAABLgAECn8qAAMgAAgJIh28GgAYAgAgAAcJYRy8GgAYAgAFAAcJRRsJSADWAQAAAA==.Vav:BAABLgAECn8UAAMPAAYJeBf4jQAJAQAPAAYJeBf4jQAJAQARAAIJswwJWgA5AAAAAA==.',
Ve='Vecnis:BAAALgAECgIJAgAAAA==.Veliette:BAAALgAECgUJBwAAAA==.Verdena:BAAALgADCgcJBwAAAA==.',
Vi='Vithper:BAAALgAECgcJEgAAAA==.',
Vn='Vnia:BAAALgADCgMJAwABLgAECgMJCAABAAAAAA==.',
Vo='Voidmuffinz:BAACLgAFFH8IAAIbAAMJ4gzeWADDAAAbAAMJ4gzeWADDAAAuAAQKfyMAAhsACQkmGHgoABQCABsACQkmGHgoABQCAAAA.',
Vy='Vynis:BAAALgAECgcJDQABLgAFFAMJCwAgAAwMAA==.Vyrahildard:BAABLgAECn8rAAIFAAgJIxxkMQAiAgAFAAgJIxxkMQAiAgAAAA==.',
Wa='Waringoutlaw:BAAALgAECgcJBwAAAA==.Wasteland:BAABLgAECn8rAAIdAAkJphGGFwCOAQAdAAkJphGGFwCOAQAAAA==.',
We='Weaselhunter:BAAALgAECgcJCwABLgAECgcJEwABAAAAAA==.Weasellock:BAAALgAECgcJEwAAAA==.Weaselmage:BAAALgAECgYJDAABLgAECgcJEwABAAAAAA==.Welor:BAAALgADCgYJDAAAAA==.',
Wh='Whatthef:BAAALgAECggJCwAAAA==.',
Wi='Wildweasel:BAAALgAECgcJDQABLgAECgcJEwABAAAAAA==.Winterhide:BAABLgAECn8qAAIJAAgJhRgWNQAXAgAJAAgJhRgWNQAXAgAAAA==.',
Xa='Xallie:BAECLgAFFH8GAAIbAAMJaQh4XQC1AAAbAAMJaQh4XQC1AAAuAAQKfzwAAhsACQkfGZ0gAD0CABsACQkfGZ0gAD0CAAAA.Xanvyr:BAABLgAECn8hAAIFAAkJXxk5NgAQAgAFAAkJXxk5NgAQAgAAAA==.Xaquillis:BAACLgAFFH8LAAMNAAQJuQrYEwCpAAAJAAMJuQ1XlADFAAANAAMJpQPYEwCpAAAuAAQKfyIAAwkACAmZGyc8AEcCAAkACAmZGyc8AEcCAA0AAQnZDs4yACwAAAAA.Xarthis:BAAALgAECgEJAQABLgAFFAQJCwANALkKAA==.',
Xe='Xentrie:BAAALgADCgUJCgAAAA==.Xeyvara:BAABLgAECn8rAAIZAAgJ6iTmAQDkAgAZAAgJ6iTmAQDkAgAAAA==.',
Xg='Xg:BAAALgADCgUJBgABLgAECgYJJgAXALwfAA==.',
Ya='Yamiyugi:BAAALgADCgUJBQAAAA==.Yatsui:BAAALgAECgQJBAAAAA==.',
Yo='Youngthug:BAAALgAECgIJAwAAAA==.',
Yu='Yutaa:BAAALgADCgYJBgAAAA==.',
Za='Zaden:BAAALgADCgUJBQAAAA==.Zarihanna:BAABLgAECn8tAAISAAgJ+hMfcwB5AQASAAgJ+hMfcwB5AQAAAA==.Zatannah:BAAALgADCgUJBQAAAA==.',
Ze='Zedryn:BAABLgAECn8mAAIQAAgJPBAmUwCWAQAQAAgJPBAmUwCWAQAAAA==.Zenshi:BAAALgAECgEJAgAAAA==.Zeperios:BAAALgAECgYJCgAAAA==.Zeril:BAABLgAECn8UAAMUAAgJjRdmCgCYAQAUAAgJjRdmCgCYAQAQAAEJHgXTPQEpAAAAAA==.Zestdruid:BAAALgAECgQJBQAAAA==.Zestull:BAABLgAECn8lAAIMAAgJnCTEBQDTAgAMAAgJnCTEBQDTAgAAAA==.Zetsuboiki:BAAALgADCgYJBgAAAA==.Zetsudeath:BAAALgADCgYJBgAAAA==.',
Zh='Zhoel:BAAALgADCgEJAQAAAA==.',
Zi='Zindeshal:BAAALgAECgYJCQAAAA==.',
Zo='Zorc:BAACLgAFFH8SAAIXAAQJhRzLEwBRAQAXAAQJhRzLEwBRAQAuAAQKfycAAhcACQmKIPsJAPQCABcACQmKIPsJAPQCAAAA.',
Zu='Zunji:BAAALgAECgEJBAAAAA==.',
Zy='Zyate:BAABLgAECn8xAAIQAAkJTRIhPgDXAQAQAAkJTRIhPgDXAQAAAA==.Zyrryn:BAABLgAECn8XAAIGAAgJwQO3EADrAAAGAAgJwQO3EADrAAAAAA==.',
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
