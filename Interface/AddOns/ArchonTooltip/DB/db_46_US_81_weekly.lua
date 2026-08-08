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

local lookup = {'Shaman-Restoration','DemonHunter-Devourer','Druid-Restoration','Druid-Feral','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Priest-Discipline','Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Priest-Shadow','DemonHunter-Vengeance','Paladin-Holy','Hunter-Marksmanship','Priest-Holy','DemonHunter-Havoc','Shaman-Elemental','Monk-Mistweaver','Warrior-Arms','Evoker-Preservation','Shaman-Enhancement','Druid-Guardian','DeathKnight-Blood','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Rogue-Assassination','Warlock-Demonology','Mage-Frost','Warrior-Protection','Evoker-Augmentation','Warrior-Fury','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=46,date='2026-08-04',data={Aa='Aarmorr:BAABLgAECn9SAAIBAAkJmhk4FgCYAgABAAkJmhk4FgCYAgAAAA==.Aatus:BAAALgAECgcJDAAAAA==.',
Ab='Absoul:BAAALgAECgQJBwAAAA==.Abyssidia:BAAALgAECgMJAwAAAA==.',
Ac='Acinianis:BAAALgAECgEJAQAAAA==.Acinthos:BAAALgAECgQJBgAAAA==.',
Ad='Addah:BAAALgAECgQJBwAAAA==.Adiros:BAAALgADCgUJBQAAAA==.',
Ae='Aechelus:BAAALgADCgEJAQABLgAECggJFQACAAceAA==.Aedelas:BAAALgAECgIJBAAAAA==.Aeloriá:BAABLgAECn9PAAMDAAkJyCBxBwBAAwADAAkJyCBxBwBAAwAEAAEJFQGgOwAPAAAAAA==.Aelyra:BAAALgAECggJEgAAAA==.',
Ag='Agrosa:BAAALgAECgYJBgAAAA==.',
Ai='Aimeeiove:BAAALgAECgYJCgAAAA==.Airad:BAAALgADCgUJBgAAAA==.Airoldeel:BAAALgAECgIJAgAAAA==.',
Al='Alcarza:BAAALgAECgMJCAAAAA==.Alchon:BAABLgAECn8kAAIFAAkJ6xqGLwAeAgAFAAkJ6xqGLwAeAgAAAA==.Aldera:BAABLgAECn88AAIBAAkJwgmSDwAoAQABAAkJwgmSDwAoAQAAAA==.Aledish:BAAALgAECgEJAgAAAA==.Alexstrayza:BAAALgAECgMJAwAAAA==.Alicien:BAABLgAECn8jAAMGAAkJwRwpSADqAQAGAAkJwRwpSADqAQAHAAEJyhBgFgA3AAAAAA==.Alista:BAAALgAECgYJCwAAAA==.Alladon:BAAALgADCgUJBQAAAA==.Allykat:BAABLgAECn9QAAMDAAgJRxlzAwATAgADAAgJRxlzAwATAgAIAAYJRxEIPwATAQAAAA==.Alorris:BAAALgAECgQJBgABLgAECgkJGQAJAFggAA==.Alunathsong:BAAALgADCgcJBwAAAA==.Alvagíngras:BAAALgAECgkJEAAAAA==.Alyra:BAAALgAECgYJBgAAAA==.',
Am='Amaith:BAACLgAFFH8KAAIKAAIJUw9OHgCNAAAKAAIJUw9OHgCNAAAuAAQKfyEAAgoACQmnGxgBAJ0CAAoACQmnGxgBAJ0CAAAA.Amantillado:BAAALgAECgUJCAABLgAECggJGQALAGIXAA==.Amata:BAAALgAECgUJCwAAAA==.Amelianne:BAAALgAECgcJEQAAAA==.Amiria:BAAALgAECgYJBgAAAA==.Ammastary:BAAALgAECgUJBwAAAA==.Ammonfrey:BAAALgAECgEJAQAAAA==.Amorfati:BAAALgAECgEJAQAAAA==.',
An='Ananiel:BAAALgADCgQJBQABLgAECgkJLwAMAA8bAA==.Andragos:BAAALgAECgQJCgAAAA==.Andrea:BAABLgAECn9KAAIEAAkJYR3oBACrAgAEAAkJYR3oBACrAgAAAA==.Andrelia:BAAALgAECgMJAwAAAA==.Angelec:BAAALgAECgEJAQAAAA==.Angelex:BAAALgAECgEJAQAAAA==.Anthria:BAAALgAECgcJEAAAAA==.',
Ao='Aoon:BAAALgAECgEJAQAAAA==.',
Ap='Apoleth:BAAALgADCgMJAwAAAA==.',
Aq='Aqules:BAAALgADCgEJAgAAAA==.',
Ar='Arand:BAAALgADCgIJAgAAAA==.Arcapeligo:BAAALgAECgEJAgAAAA==.Archonsfury:BAAALgAECggJDwAAAA==.Arilyn:BAAALgAECgMJAwAAAA==.Array:BAAALgAECgUJBQAAAA==.',
As='Asath:BAAALgAECgYJDAAAAA==.Ascended:BAAALgAECgEJAgABLgADCgkJCQANAAAAAA==.Asheye:BAAALgAECgkJCwABLgAFFAMJBQAGAPUQAA==.Ashogar:BAAALgAECgUJBQAAAA==.Ashuranadi:BAAALgADCgcJBwAAAA==.Askir:BAAALgADCgMJAwAAAA==.Asnew:BAAALgAECgkJEQAAAA==.Asura:BAAALgAECgkJEwAAAA==.Asyllaa:BAABLgAECn8eAAMOAAkJFx+LLABPAgAOAAcJOyOLLABPAgAPAAYJ9hLNHwAWAQAAAA==.',
At='Athelstan:BAAALgADCgIJAgAAAA==.Atnawuerus:BAAALgAECgEJAQAAAA==.Atonement:BAABLgAECn8aAAMJAAkJJBqFFAA5AgAJAAgJNh2FFAA5AgAQAAQJLgkTcwBbAAABLgAFFAMJCAARAOkhAA==.',
Au='Aumaril:BAABLgAECn8mAAMSAAgJ4hdMAwD9AQASAAgJ4hdMAwD9AQAOAAgJBxl5EQBLAQAAAA==.Auralynn:BAABLgAECn8qAAIOAAkJUAl/kgBOAQAOAAkJUAl/kgBOAQAAAA==.',
Av='Avathar:BAAALgAECgMJBgAAAA==.Averina:BAAALgAECgMJAwAAAA==.Averus:BAABLgAECn9SAAIIAAkJuhLJHQDaAQAIAAkJuhLJHQDaAQAAAA==.',
Az='Azariel:BAABLgAECn8+AAIOAAkJ5BPmUwDOAQAOAAkJ5BPmUwDOAQAAAA==.Azenwraith:BAAALgADCgkJCQAAAA==.Azuriah:BAABLgAECn9MAAMPAAkJ6B3/BQCLAgAPAAkJIB3/BQCLAgAOAAEJXyHCTgFfAAAAAA==.',
Ba='Baane:BAAALgAECgUJCAABLgAECgcJEwANAAAAAA==.Babnik:BAEBLgAECn8YAAMFAAkJZBPkEwA5AQAFAAkJZBPkEwA5AQATAAIJPw0IMABYAAAAAA==.Bagel:BAACLgAFFH8eAAMSAAUJHCNeDQDhAQASAAUJHCNeDQDhAQAOAAQJaQf0OgCwAAAuAAQKfxkAAxIACAmCH1AmAPYBABIACAmCH1AmAPYBAA4AAQnkCrKpASsAAAAA.Baldwin:BAAALgAECgUJBQAAAA==.Ballbreaker:BAAALgAECgQJBAAAAA==.Baminenherb:BAAALgADCgUJBQAAAA==.Bazluz:BAAALgADCgIJAwAAAA==.',
Be='Bearbone:BAAALgAECgIJAwAAAA==.Bearlysoberr:BAAALgAECgUJBQAAAA==.Bedhead:BAABLgAECn9DAAQJAAkJpRdwEQBdAgAJAAkJ7BZwEQBdAgAUAAMJFBx6VQDgAAAQAAEJKwrXjgAsAAAAAA==.Bedrocked:BAAALgAECgIJAwAAAA==.Belaim:BAAALgAECgIJAgAAAA==.Belovis:BAACLgAFFH8fAAIOAAYJiCS1GQCkAQAOAAYJiCS1GQCkAQAuAAQKfyYAAg4ACQk0JOgMACYDAA4ACQk0JOgMACYDAAAA.Berathor:BAAALgAECgkJEwAAAA==.Betsea:BAAALgAECgUJBQABLgAECgkJOgASAGYTAA==.',
Bi='Bidoof:BAABLgAECn86AAIVAAkJvBEHBQCIAQAVAAkJvBEHBQCIAQAAAA==.Bigblunt:BAAALgADCgcJEgAAAA==.Bigear:BAAALgAECgQJBAAAAA==.Bigjohnii:BAAALgADCgcJBwAAAA==.Birdi:BAAALgAECgEJAwAAAA==.Bitemarks:BAAALgADCgcJDgAAAA==.',
Bl='Blackcoat:BAAALgAECgYJDwAAAA==.Bluedragan:BAAALgAECgQJBAABLgAFFAMJCgAJALMRAA==.',
Bo='Boggrog:BAAALgAECgYJCQABLgAECgUJCwANAAAAAA==.Bolz:BAAALgAECgMJAwAAAA==.Boosch:BAAALgADCgIJAgAAAA==.Boras:BAAALgADCgEJAQABLgAECggJGwACAMMYAA==.Bosshog:BAABLgAECn80AAIWAAkJpAvuNgBeAQAWAAkJpAvuNgBeAQAAAA==.Bowgobrr:BAABLgAECn8qAAMTAAgJ4xXlDgBvAQATAAgJ4xXlDgBvAQAFAAYJ2QpW3QCTAAABLgAFFAkJNwAFAMsWAA==.',
Br='Braelyne:BAABLgAECn8WAAIOAAYJdR3JXwDEAQAOAAYJdR3JXwDEAQAAAA==.Brasnite:BAAALgADCgEJAQAAAA==.Brewrock:BAAALgAECgQJCAAAAA==.Brewtilus:BAAALgAECgQJBwAAAA==.Brolaf:BAAALgAECgUJBQAAAA==.Broseidon:BAAALgAECgcJEQAAAA==.Bryst:BAAALgADCgQJBAAAAA==.',
Bu='Buffsalot:BAAALgAECgUJDgAAAA==.Buffwarlock:BAAALgAECgcJBwAAAA==.Bullbatoo:BAAALgAECgEJAQAAAA==.Burlycheeks:BAABLgAECn85AAIOAAkJPCCTGACwAgAOAAkJPCCTGACwAgAAAA==.',
Ca='Calav:BAAALgAECgYJBgAAAA==.Caliista:BAAALgADCggJCAAAAA==.Carlitocool:BAAALgADCgIJAgAAAA==.Carraxus:BAAALgAECgQJDAAAAA==.Cassidyn:BAAALgADCgcJCAAAAA==.Castle:BAABLgAECn8ZAAMOAAcJyh09bwCQAQAOAAYJGBw9bwCQAQASAAYJZwmQDADOAAAAAA==.Catsinhats:BAAALgAECgUJBAABLgAFFAQJFAAGAC8OAA==.Catsneverdie:BAAALgAFFAEJAQABLgAFFAQJFAAGAC8OAA==.Catzinhatz:BAABLgAECn8YAAICAAcJAgq/jgADAQACAAcJAgq/jgADAQABLgAFFAQJFAAGAC8OAA==.',
Ce='Cecelya:BAABLgAECn9AAAQUAAkJ5RlLFwAUAgAUAAkJ5RlLFwAUAgAQAAcJNhGCNABGAQAJAAMJUw1iXACOAAAAAA==.Celerian:BAAALgAECgEJAQAAAA==.Celibate:BAAALgAECgUJBgAAAA==.Celothor:BAAALgADCgYJBgAAAA==.Celticmoon:BAAALgADCgQJBAAAAA==.',
Ch='Cherlia:BAABLgAECn8cAAIWAAYJIhO2RQAyAQAWAAYJIhO2RQAyAQABLgAECgkJHgAVAFciAA==.Chillykiller:BAAALgAECgYJBwABLgAECgkJHgAVAFciAA==.Chiva:BAAALgAECgQJBAABLgAFFAMJBQABAO4KAA==.Chivactdl:BAAALgAECgMJBAABLgAFFAMJBQABAO4KAA==.Chivalt:BAAALgAECgEJAQABLgAFFAMJBQABAO4KAA==.Chonch:BAAALgAECgIJAgAAAA==.Chozen:BAAALgAECggJCwAAAA==.Chunknoriss:BAABLgAECn8vAAMXAAYJYiD3HQApAgAXAAYJYiD3HQApAgALAAMJWwWbdwBhAAABLgAFFAMJBQABAO4KAA==.',
Ci='Cigarettes:BAABLgAECn8XAAIYAAYJsRXBBgDxAAAYAAYJsRXBBgDxAAAAAA==.',
Cl='Claudiuss:BAAALgAECgYJDAABLgAFFAMJCgABAGcPAA==.Clurefu:BAABLgAECn84AAMXAAkJvCEQBQBaAwAXAAkJvCEQBQBaAwALAAMJ5BZVWACuAAABLgAFFAMJDQADAK8dAA==.Clurelock:BAACLgAFFH8NAAIDAAMJrx2vEQD7AAADAAMJrx2vEQD7AAAuAAQKf0AAAgMACQn6Ii4EAHsDAAMACQn6Ii4EAHsDAAAA.Cluremage:BAAALgAECgYJEQAAAA==.Clurethyr:BAABLgAECn8rAAIZAAgJzB98AADdAgAZAAgJzB98AADdAgABLgAFFAMJDQADAK8dAA==.',
Co='Cobblestone:BAAALgAECgIJAgAAAA==.Codenameknd:BAAALgAECgIJAgAAAA==.Comsuck:BAAALgAECgcJEQAAAA==.Conchobhar:BAABLgAECn8VAAIXAAkJlBoMGgBHAgAXAAkJlBoMGgBHAgAAAA==.Constella:BAAALgADCgYJCQAAAA==.Coppertan:BAAALgAECgMJBQAAAA==.Coralyne:BAAALgADCgEJAQAAAA==.Corrosion:BAABLgAECn8wAAIaAAkJUx44AQA2AgAaAAkJUx44AQA2AgAAAA==.',
Cr='Crazyshammy:BAAALgAECgkJEgAAAA==.Crommash:BAAALgAECgcJCgAAAA==.Crono:BAAALgAECgQJCQAAAA==.Crunchynuget:BAABLgAECn8pAAIOAAkJbSDMAwCcAgAOAAkJbSDMAwCcAgABLgAFFAYJGgAOABAeAA==.',
Ct='Cthuwu:BAAALgAECgMJAwABLgAFFAcJEwAFAN8VAA==.',
Cu='Cujotaro:BAAALgAECgEJAgAAAA==.Cumberdale:BAAALgAECgUJBQAAAA==.',
Cv='Cvhamster:BAAALgAECgQJCgAAAA==.',
Cy='Cybeast:BAABLgAECn81AAMEAAkJkh54BAC4AgAEAAkJhB54BAC4AgAbAAUJFRh3BQBWAQAAAA==.Cynortas:BAAALgAECgIJBgAAAA==.',
Da='Daciana:BAABLgAECn8hAAIFAAkJ7BA7GAATAQAFAAkJ7BA7GAATAQAAAA==.Dados:BAABLgAECn8wAAMUAAkJXh5tDgCBAgAUAAkJXh5tDgCBAgAQAAEJsBRKgAA9AAAAAA==.Daeghun:BAAALgAECgIJBQAAAA==.Dahleigh:BAAALgADCgkJDQAAAA==.Dakanar:BAAALgAECgQJCgAAAA==.Dambrien:BAAALgAECgUJBQAAAA==.Daravus:BAAALgAECgUJCAAAAA==.Darkfox:BAAALgAECgEJAQAAAA==.Darkhazel:BAAALgAECgEJAQAAAA==.Darkkromdor:BAABLgAECn8zAAIOAAkJtR/SFwC0AgAOAAkJtR/SFwC0AgAAAA==.Darloct:BAAALgAECggJEwAAAA==.Dazzlor:BAAALgADCggJCAAAAA==.',
De='Deadelff:BAABLgAECn8kAAMCAAgJ2hZHYwBhAQAVAAYJexvxJwCDAQACAAgJQg9HYwBhAQAAAA==.Deadholypaly:BAAALgADCgEJAwAAAA==.Deadlifts:BAAALgAECgQJCQAAAA==.Deadlighted:BAAALgADCgcJDgABLgAECggJJAACANoWAA==.Deadslinger:BAAALgADCgYJDAAAAA==.Deadtotem:BAAALgADCgkJCQABLgAECggJJAACANoWAA==.Deammon:BAAALgAECgEJAQAAAA==.Deathcat:BAACLgAFFH8UAAIGAAQJLw7mSgDCAAAGAAQJLw7mSgDCAAAuAAQKfzsAAgYACQmjFgc4AB8CAAYACQmjFgc4AB8CAAAA.Deathkiss:BAAALgAECgYJEgAAAA==.Deathpheonix:BAAALgAECgQJBwAAAA==.Deathrat:BAAALgADCgUJBgAAAA==.Deathrixx:BAABLgAFFH8RAAQGAAUJZx4JVABKAQAGAAUJQh4JVABKAQAHAAIJhB3QHACdAAAcAAEJIBhWPABEAAAAAA==.Deathshadowx:BAAALgAECgYJDAAAAA==.Delryth:BAAALgAECgQJBAAAAA==.Denajah:BAAALgAECgIJAgAAAA==.',
Df='Dfault:BAAALgADCgEJAQAAAA==.',
Di='Discharged:BAAALgAECgQJBAABLgAECggJGQALAGIXAA==.',
Dk='Dkdeathblade:BAAALgAECgEJAQAAAA==.Dkpheonix:BAABLgAECn80AAIQAAkJ6xWoGAABAgAQAAkJ6xWoGAABAgAAAA==.',
Do='Dolemite:BAABLgAECn9HAAMXAAcJHhYdLwC/AQAXAAcJHhYdLwC/AQALAAcJcRkxAwC3AQAAAA==.Donalbain:BAACLgAFFH8KAAIBAAMJZw+8UwCqAAABAAMJZw+8UwCqAAAuAAQKfzAAAgEACQkCHgsDAIcCAAEACQkCHgsDAIcCAAAA.Dotdotgoose:BAAALgAECgQJCAAAAA==.',
Dr='Draconz:BAAALgAECgIJAgABLgAECgcJEwANAAAAAA==.Draganpriest:BAABLgAFFH8KAAIJAAMJsxFyHwCSAAAJAAMJsxFyHwCSAAAAAA==.Draganussy:BAAALgADCgEJAQABLgAFFAMJCgAJALMRAA==.Draggo:BAAALgAECgEJAQAAAA==.Drakkira:BAAALgADCgYJBgAAAA==.Draxon:BAAALgAECgEJAQAAAA==.Dremar:BAABLgAECn8fAAMdAAkJ2BDVAwAvAQAdAAgJkQ/VAwAvAQAeAAYJRAyRGQDXAAAAAA==.Druc:BAAALgAECgEJAgAAAA==.',
Du='Durock:BAAALgAECgMJBAAAAA==.',
Dy='Dynaris:BAAALgADCgMJAwAAAA==.',
Ei='Eianna:BAAALgAECgEJAQAAAA==.',
El='Elcachazo:BAAALgAECgIJAgAAAA==.Eldinn:BAAALgADCgcJBgAAAA==.Eleanni:BAAALgAECgQJBAAAAA==.Elenora:BAAALgAECgMJAwAAAA==.Elidor:BAABLgAECn8XAAQIAAgJNwseUADNAAAIAAYJkAweUADNAAADAAQJJxAHFABvAAAbAAQJbQLKHgA8AAAAAA==.Ellalangley:BAAALgAECgIJAwABLgAFFAMJBQAGAPUQAA==.Elthelas:BAAALgADCgEJAQAAAA==.Eluneatic:BAAALgADCggJCgAAAA==.Elyssaris:BAABLgAECn84AAIcAAkJ4xoyDgAnAgAcAAkJ4xoyDgAnAgAAAA==.Elzulkin:BAAALgADCgcJCgAAAA==.',
Em='Emmdeath:BAABLgAECn8YAAIGAAYJ7QNWDgGaAAAGAAYJ7QNWDgGaAAAAAA==.Emmils:BAABLgAECn8+AAIIAAkJfA1uKgCBAQAIAAkJfA1uKgCBAQAAAA==.Emìly:BAABLgAECn9VAAQLAAkJGiQiAwAyAwALAAkJGiQiAwAyAwAXAAkJCxaKHwAeAgAMAAUJRRUqRgDiAAAAAA==.',
En='Enderelvarg:BAABLgAFFH8FAAIfAAUJbw9TBQARAQAfAAUJbw9TBQARAQAAAA==.Endmicrobuys:BAAALgADCgUJBQAAAA==.Entaria:BAACLgAFFH8GAAIOAAQJmhmFMQBOAQAOAAQJmhmFMQBOAQAuAAQKf0EABA4ACQk7IYMOAPICAA4ACQk7IYMOAPICAA8ABwkxH24NAO4BABIABgm1DGJbAMgAAAAA.',
Eo='Eox:BAAALgADCgMJAwAAAA==.',
Ep='Episkey:BAABLgAECn8gAAMIAAkJMhKOJgCZAQAIAAkJMhKOJgCZAQADAAQJdRcgYQASAQAAAA==.',
Er='Erindaglaze:BAAALgADCgQJBQAAAA==.Erissae:BAAALgADCgEJAgAAAA==.Eropor:BAABLgAECn8iAAMXAAYJexPyQQBlAQAXAAYJexPyQQBlAQALAAMJYQbMigBHAAABLgAFFAQJGAADAEIRAA==.Eroversion:BAACLgAFFH8YAAMDAAQJQhFrMwDgAAADAAQJQhFrMwDgAAAIAAEJtwHVMwAfAAAuAAQKf1YABQMACQlCHq8XAIkCAAMACQlCHq8XAIkCAAgABAkIFj5UANUAAAQAAwm4DUszAJEAABsAAQkAAFWVAAAAAAAA.Eroward:BAAALgAECgYJDAABLgAFFAQJGAADAEIRAA==.',
Es='Esmay:BAABLgAECn8fAAIWAAkJHRRNIADhAQAWAAkJHRRNIADhAQAAAA==.Eso:BAAALgADCgYJCwAAAA==.',
Et='Ethren:BAABLgAECn9RAAIgAAkJ2RgJBABeAgAgAAkJ2RgJBABeAgAAAA==.',
Eu='Eudeyrn:BAAALgAECgYJAwAAAA==.',
Ev='Evilrepu:BAAALgAECgEJAQAAAA==.',
Ey='Eyebrows:BAAALgAECgIJAgAAAA==.',
Ez='Ezikarridge:BAAALgAECgIJAgAAAA==.',
Fa='Faker:BAAALgADCgEJAQAAAA==.Falcone:BAAALgAECgMJBgAAAA==.',
Fe='Felbolter:BAABLgAFFH8FAAIeAAQJFBB4AwAbAQAeAAQJFBB4AwAbAQAAAA==.Feliri:BAAALgAECggJEgAAAA==.',
Fi='Fiddlefaddle:BAAALgAFFAEJAQAAAA==.Filgulfin:BAABLgAECn9bAAMFAAkJBCC8EADLAgAFAAkJBCC8EADLAgATAAgJgRDREwAkAQAAAA==.Finkate:BAABLgAECn8XAAIFAAgJHA4FYwB/AQAFAAgJHA4FYwB/AQAAAA==.Firebad:BAABLgAECn8wAAMeAAkJpxy5AgCFAgAeAAkJpxy5AgCFAgAhAAYJHwrG5ACTAAAAAA==.Firebringer:BAABLgAECn9VAAICAAkJ9A7jSgCmAQACAAkJ9A7jSgCmAQAAAA==.Fistokaestey:BAAALgADCgkJEgABLgAECgkJIwAiANUXAA==.',
Fl='Flaakk:BAAALgADCgcJBwAAAA==.Flamehunter:BAABLgAECn8iAAMCAAkJMRqEHACnAgACAAkJcRmEHACnAgAVAAcJLRdgJACaAQAAAA==.Flo:BAABLgAECn9aAAMQAAkJhxwZCwCeAgAQAAkJhxwZCwCeAgAUAAMJSAcyWAB5AAAAAA==.Floki:BAABLgAECn8UAAIjAAkJqhJnHQBKAQAjAAkJqhJnHQBKAQAAAA==.Flora:BAAALgAECgQJBAAAAA==.Flowing:BAABLgAECn8wAAIkAAkJyxmdAgDCAQAkAAkJyxmdAgDCAQAAAA==.',
Fo='Foods:BAACLgAFFH8bAAMlAAMJiRMfHQC+AAAlAAMJiRMfHQC+AAAjAAIJBgt2FwBpAAAuAAQKf4YABCUACQm1HmICAFMCACUACQm1HmICAFMCACMACAlkFV0EAFwBABgAAwnoDE0wAHUAAAAA.Foofsmash:BAAALgADCgUJBgAAAA==.',
Fr='Fripouille:BAAALgADCgMJAwAAAA==.',
Fu='Fustín:BAAALgAECgYJEgAAAA==.Fuzzyewok:BAAALgAECgYJEwAAAA==.',
['Fø']='Føøds:BAAALgADCgMJAwAAAA==.',
Ga='Gaboo:BAAALgAECgkJEwAAAA==.Galangal:BAAALgAECgIJAgAAAA==.Garfman:BAAALgAFFAEJAQAAAA==.Garthrall:BAAALgAECgEJAQAAAA==.',
Gb='Gb:BAACLgAFFH8HAAISAAYJExDZHgAmAQASAAYJExDZHgAmAQAuAAQKfxQAAhIABwknIYUSAH0CABIABwknIYUSAH0CAAEuAAUUBAkNABAA8hoA.',
Gh='Ghostinhale:BAABLgAECn8dAAIGAAcJ2RbUEAApAQAGAAcJ2RbUEAApAQAAAA==.',
Gi='Gibbshole:BAAALgADCgcJBwAAAA==.Gilorion:BAABLgAECn8XAAIFAAkJ7RbnMgARAgAFAAkJ7RbnMgARAgAAAA==.',
Gl='Glasgoww:BAAALgAECgYJCQABLgAFFAMJCgABAGcPAA==.Gløck:BAAALgAECgIJAgAAAA==.',
Gn='Gnibat:BAAALgAECgQJBwAAAA==.Gnomerlicous:BAAALgADCgkJCQAAAA==.',
Go='Goburina:BAACLgAFFH8VAAMBAAQJohUZHgDdAAABAAQJohUZHgDdAAAWAAEJ2wEVQQAjAAAuAAQKfxgAAgEACQlaC1M9AIwBAAEACQlaC1M9AIwBAAAA.Golias:BAAALgADCgEJAQAAAA==.Gonahrhea:BAAALgAECgEJAQAAAA==.',
Gr='Grenache:BAAALgAECgcJCAABLgAECgcJCAANAAAAAA==.Grievo:BAAALgAECgYJCQAAAA==.Grimdawn:BAAALgAFFAEJAQAAAA==.Grimfist:BAAALgAECgMJAwAAAA==.Grimtankdrud:BAAALgAECgEJAQABLgAECggJGgARAL0PAA==.Grinnir:BAAALgAECgQJBgABLgAECggJGwACAMMYAA==.',
Gu='Guildenstern:BAAALgADCgUJBQABLgAFFAMJCgABAGcPAA==.Gulpron:BAAALgAECgYJCgAAAA==.',
Gy='Gypsiey:BAAALgAECgUJBQAAAA==.',
['Gí']='Gímlí:BAACLgAFFH8LAAIFAAMJABdSNgDMAAAFAAMJABdSNgDMAAAuAAQKfzgAAgUACQm8HiQdAHYCAAUACQm8HiQdAHYCAAAA.',
Ha='Halcyndraag:BAABLgAECn9SAAQkAAkJZxUrIQDQAQAkAAcJaxUrIQDQAQAfAAMJwBcBGgCBAAAZAAEJPQJWRAAeAAAAAA==.Handbannana:BAAALgAECgQJBAAAAA==.Handsome:BAAALgAECgcJDAABLgAECgkJGQAQADQJAA==.Happydk:BAACLgAFFH8RAAMGAAQJniCPPgB6AQAGAAQJniCPPgB6AQAcAAMJKRHrLACVAAAuAAQKfygAAwYACQkdI2MXALoCAAYACQlaIWMXALoCABwABwlKGSMnABsBAAAA.Hartu:BAABLgAECn9NAAIjAAkJfxTyDwDpAQAjAAkJfxTyDwDpAQAAAA==.Harukasan:BAAALgADCgIJAgAAAA==.Hashpipe:BAAALgADCgMJAwAAAA==.Hazl:BAAALgAECgMJBAAAAA==.',
He='Healortank:BAAALgAECgEJAQAAAA==.Healsofpain:BAAALgADCgYJBgAAAA==.Healtardo:BAAALgAFFAIJAgAAAA==.Heiro:BAAALgAFFAEJAQABLgAFFAUJDAAZAEQIAA==.Hellankeller:BAAALgAECgQJBwAAAA==.Hemic:BAACLgAFFH8TAAIKAAMJMB/gEQD1AAAKAAMJMB/gEQD1AAAuAAQKfzQAAwoACQlGI18FAN0CAAoACQlGI18FAN0CACAABAnwGhUQACMBAAAA.Hemmorage:BAAALgAECgYJCgABLgAFFAMJBQAGAPUQAA==.Herbalmist:BAAALgAECgYJDAAAAA==.',
Hi='Higag:BAAALgADCgQJBAAAAA==.Hinaba:BAAALgADCgMJAwAAAA==.Hippypally:BAAALgADCgEJAQAAAA==.Hircine:BAAALgAECgQJBQAAAA==.',
Ho='Holysea:BAAALgAECgYJDAABLgAECgkJOgASAGYTAA==.Horatio:BAAALgAECgEJAQABLgAFFAMJCgABAGcPAA==.',
Hr='Hraken:BAAALgAECgUJBgAAAA==.',
Hu='Hukruun:BAAALgADCgEJAgAAAA==.Huntrinei:BAAALgAECgYJCgAAAA==.',
['Hé']='Hélénkéller:BAAALgADCggJDwABLgAFFAMJCAAFABUYAA==.',
Ia='Iahawkeye:BAAALgAECgEJAQAAAA==.',
Ib='Ibhuntin:BAAALgAECggJEgAAAA==.',
Ic='Icyhooves:BAAALgAECgEJAQAAAA==.',
Id='Idiocracy:BAABLgAECn8lAAMjAAkJbhY/DQAWAgAjAAkJrRU/DQAWAgAlAAgJ2w7uMACJAQAAAA==.Idk:BAAALgADCgYJCgAAAA==.',
Ik='Ikodiwa:BAAALgAECgUJCAAAAA==.',
Il='Illigirl:BAAALgADCgEJAQAAAA==.',
Im='Imwithfloki:BAAALgAECgMJBgAAAA==.',
In='Indoti:BAAALgADCgUJBwAAAA==.',
Ir='Ironmark:BAAALgAECgUJCAAAAA==.Irys:BAAALgAECgMJAwAAAA==.',
Is='Isam:BAAALgADCgYJBgAAAA==.Isamidor:BAACLgAFFH8QAAIFAAYJlBsAKABnAQAFAAYJlBsAKABnAQAuAAQKfxwAAgUACQmXI+cEAD8DAAUACQmXI+cEAD8DAAAA.Ismokeu:BAACLgAFFH8aAAMUAAQJpBj7CgD6AAAUAAQJbxf7CgD6AAAJAAQJMgogFwDMAAAuAAQKfzoAAhQACQmrGZ4NAIwCABQACQmrGZ4NAIwCAAAA.Ismyn:BAAALgAECgYJBwAAAA==.',
It='Itskemba:BAAALgADCgYJBgAAAA==.',
Iy='Iyania:BAAALgADCgIJAgAAAA==.',
Iz='Izayoi:BAAALgADCgcJCQAAAA==.',
Ja='Jackoneal:BAABLgAECn8jAAIOAAkJyQcYpwAtAQAOAAkJyQcYpwAtAQAAAA==.Jalidelo:BAABLgAECn9KAAMJAAkJFR6cCADrAgAJAAkJFR6cCADrAgAUAAEJ5gZihgAqAAAAAA==.Jaliwind:BAAALgADCgkJCQAAAA==.Jayan:BAAALgAECgEJAQAAAA==.',
Je='Jenifurr:BAAALgADCgIJAgAAAA==.Jenyx:BAAALgAECgUJCwAAAA==.',
Ji='Jimbowaboki:BAAALgAECgEJAQAAAA==.',
Jo='Johan:BAABLgAECn8eAAIhAAkJMhqFLAAnAgAhAAkJMhqFLAAnAgAAAA==.Jokers:BAABLgAECn8jAAMjAAYJXBVyBwDbAAAlAAUJ4g/8WQDoAAAjAAYJShRyBwDbAAAAAA==.Jokersfists:BAABLgAECn8XAAICAAYJVg/5GQCyAAACAAYJVg/5GQCyAAAAAA==.Joranbragi:BAABLgAECn8xAAMOAAgJdgzfHQDjAAAOAAcJCQzfHQDjAAAPAAMJjAhDDwBlAAAAAA==.Jordanjr:BAAALgAECggJEQAAAA==.Jormun:BAAALgADCgEJAQAAAA==.Joshy:BAABLgAECn8dAAIdAAYJsRCBDgBJAQAdAAYJsRCBDgBJAQAAAA==.Jotoonice:BAABLgAECn8aAAIiAAgJjBVjYQC9AQAiAAgJjBVjYQC9AQAAAA==.',
Jt='Jtoothaordan:BAACLgAFFH8YAAQmAAcJexZ0CgDsAAAmAAUJzBN0CgDsAAATAAMJsg0uLQBWAAAFAAIJAwgNqwBCAAAuAAQKfy4ABCYACAn9Hw8UAAUCABMACAn9F60gACACACYABgkaJA8UAAUCAAUAAglIIaDPAKsAAAAA.',
Ju='Juglfhednar:BAAALgADCgEJAQAAAA==.Jules:BAAALgAECgUJBQAAAA==.Justbob:BAAALgAECgUJBgAAAA==.',
['Jú']='Júgg:BAAALgAECgQJBgAAAA==.',
Ka='Kaachow:BAABLgAECn8uAAIDAAkJZR+DCQAiAwADAAkJZR+DCQAiAwAAAA==.Kaana:BAABLgAECn9QAAIFAAkJ7xmlHwBpAgAFAAkJ7xmlHwBpAgAAAA==.Kaelenil:BAAALgAECgEJAQAAAA==.Kaestey:BAAALgAECggJDQABLgAECgkJIwAiANUXAA==.Kairis:BAAALgAECgYJCQABLgAFFAUJKAADABYkAA==.Kalia:BAAALgAECgEJAQABLgAECgkJOAAcAOMaAA==.Kallista:BAAALgADCgEJAQAAAA==.Kanoalandiwa:BAAALgAECgEJAQAAAA==.Karthagon:BAABLgAECn8tAAIOAAkJfxz/AwCSAgAOAAkJfxz/AwCSAgAAAA==.Karungash:BAACLgAFFH8LAAMhAAQJqgoMZAD/AAAhAAQJqgoMZAD/AAAeAAEJVQE+GwA+AAAuAAQKfx0AAyEACAm1Id4QAPMCACEACAm1Id4QAPMCAB4AAgkTEk1SAHcAAAAA.Karva:BAABLgAECn8kAAIRAAkJzBqWBgAqAgARAAkJzBqWBgAqAgAAAA==.Karvy:BAABLgAECn8kAAIbAAgJXB7EAwCeAQAbAAgJXB7EAwCeAQABLgAECgkJJAARAMwaAA==.Kash:BAAALgADCgUJBQABLgAFFAUJEwAEACYlAA==.Kayzer:BAAALgADCgYJGAAAAA==.',
Ke='Kelonaar:BAACLgAFFH8bAAIWAAYJ9x9eDABxAQAWAAYJ9x9eDABxAQAuAAQKfygAAxYACQksIqEWADECABYACQksIqEWADECABoAAgn1Gg45AEoAAAAA.Kelya:BAAALgAECgUJBQABLgAFFAYJGwAWAPcfAA==.Kerrie:BAAALgADCgEJAQAAAA==.',
Kh='Kharys:BAAALgAECgUJCwAAAA==.Khthonious:BAABLgAECn8VAAICAAcJBx4TOwDbAQACAAcJBx4TOwDbAQAAAA==.',
Ki='Kibblsncrits:BAAALgAECgIJAwABLgAECgkJEgANAAAAAA==.Kickingdonut:BAACLgAFFH8FAAILAAMJNx8sHADtAAALAAMJNx8sHADtAAAuAAQKfywAAwsACAk7IxkJAOcCAAsACAk7IxkJAOcCAAwABgn1GUI3AG4BAAAA.Killerhottie:BAAALgAECgEJAQAAAA==.Killermoomoo:BAAALgAECgUJCwAAAA==.Kinoh:BAAALgADCgkJEAAAAA==.Kittykarma:BAAALgAECgUJBQAAAA==.',
Kl='Kloverr:BAAALgAECgIJAgAAAA==.Klub:BAAALgADCgYJBgAAAA==.',
Ko='Kollita:BAAALgAECgEJAQAAAA==.Komatsu:BAAALgAECgEJAQAAAA==.Kombatkarl:BAAALgAECgEJAQAAAA==.Koramere:BAAALgADCgcJBwAAAA==.',
Kr='Kretaios:BAAALgADCgQJBAAAAA==.Kromir:BAAALgAECgQJBwAAAA==.Kromnar:BAAALgADCgEJAQAAAA==.Kronixrage:BAAALgAECgYJCwAAAA==.Kronn:BAAALgAECgYJBwAAAA==.Krooler:BAAALgAECgQJCAAAAA==.Krum:BAACLgAFFH8gAAIOAAUJaR8DKQBnAQAOAAUJaR8DKQBnAQAuAAQKfx4AAg4ACAmsHYRRANQBAA4ACAmsHYRRANQBAAAA.',
Ku='Kungfoumoo:BAAALgAECgEJAQAAAA==.',
La='Ladgarkk:BAAALgADCggJFQAAAA==.Lanval:BAABLgAECn9eAAIOAAkJgBtIIgB9AgAOAAkJgBtIIgB9AgAAAA==.Lardend:BAABLgAECn8bAAIVAAgJsAlWCgDqAAAVAAgJsAlWCgDqAAAAAA==.Latinlover:BAAALgADCgEJAQAAAA==.Laurian:BAAALgADCgcJDwAAAA==.Laurì:BAAALgAECgMJBQABLgAECgkJVQALABokAA==.',
Le='Leaky:BAAALgAECgIJBAAAAA==.Leetah:BAACLgAFFH8bAAIbAAMJ0R+NCAAJAQAbAAMJ0R+NCAAJAQAuAAQKf48AAxsACQmdIp0AAAwDABsACQmdIp0AAAwDAAQABQkuICsDAHMBAAAA.Leftblank:BAABLgAECn8UAAMGAAgJOAn1FQD4AAAGAAgJOAn1FQD4AAAHAAQJPAPcLgBkAAAAAA==.Legitimas:BAAALgAECgEJAQAAAA==.Lemix:BAAALgAECgMJDAAAAA==.Letmetameyou:BAAALgAECgYJBgAAAA==.',
Li='Liasong:BAAALgADCgMJAwAAAA==.Lilyandra:BAAALgADCgkJEAAAAA==.Lilyara:BAAALgADCgIJAgAAAA==.Lilyoptra:BAABLgAECn8VAAIhAAcJKwPwLQBHAAAhAAcJKwPwLQBHAAABLgAECgkJFwAIADcLAA==.Lindrael:BAAALgADCgEJAQAAAA==.Liszt:BAAALgAECgYJBgAAAA==.Litallya:BAAALgAECggJDQAAAA==.Littletush:BAABLgAECn8dAAIFAAkJNAwwDgCAAQAFAAkJNAwwDgCAAQAAAA==.Livingdemon:BAAALgAECgUJDwAAAA==.',
Lm='Lminus:BAAALgAECgYJEgAAAA==.',
Lo='Lockolus:BAAALgAECgMJAwAAAA==.Lockpockets:BAAALgADCgEJAQAAAA==.Longshot:BAAALgAECgIJAgABLgAECgUJCwANAAAAAA==.Lootie:BAAALgAECggJDgAAAA==.Loriane:BAAALgAECgUJCAABLgAECgkJKAADAAIgAA==.Lorianth:BAAALgADCgcJDgAAAA==.Lotharbacco:BAAALgAECgMJAwAAAA==.Lovegood:BAAALgADCgEJAQAAAA==.Loveisbeauty:BAAALgAECgUJBwAAAA==.Lowki:BAAALgAECgEJAgAAAA==.',
Ly='Lychi:BAAALgAECgYJDAAAAA==.Lylora:BAACLgAFFH8oAAIDAAUJFiSSBgADAgADAAUJFiSSBgADAgAuAAQKf08AAgMACQm8JOIBALoDAAMACQm8JOIBALoDAAAA.Lysera:BAAALgADCgMJAwAAAA==.',
['Lê']='Lêmonaide:BAABLgAECn8tAAMUAAkJTQ+oJgCQAQAUAAkJTQ+oJgCQAQAQAAUJAgXEagBzAAAAAA==.',
Ma='Madesh:BAABLgAECn9LAAMRAAkJYxv+BQA8AgARAAkJtxj+BQA8AgACAAkJZBozKAAqAgAAAA==.Madman:BAABLgAECn8vAAIXAAkJTA9jOQCMAQAXAAkJTA9jOQCMAQAAAA==.Maelle:BAABLgAECn9SAAIOAAkJ2iJZDAACAwAOAAkJ2iJZDAACAwAAAA==.Magekaestey:BAABLgAECn8jAAIiAAkJ1RfHPAAnAgAiAAkJ1RfHPAAnAgAAAA==.Majandra:BAAALgAECgUJDAAAAA==.Malala:BAAALgAECgcJDQABLgAFFAIJEwAUAD4dAA==.Malyndra:BAABLgAECn8yAAMVAAkJaBwEDwA1AgAVAAkJvxoEDwA1AgARAAYJ9hksDgBvAQAAAA==.Malyssa:BAAALgADCgIJAgAAAA==.Marianne:BAAALgADCgYJBwAAAA==.Marle:BAAALgAECgEJBAAAAA==.Marvolt:BAABLgAECn8YAAIhAAgJcA0RbQBiAQAhAAgJcA0RbQBiAQAAAA==.Masy:BAAALgAECgEJAQAAAA==.',
Mc='Mcrae:BAAALgAECgYJBwAAAA==.',
Md='Md:BAAALgAECgEJAgAAAA==.',
Me='Medrare:BAAALgAECgEJAQAAAA==.Meekastraza:BAAALgAECgIJAgAAAA==.Melon:BAAALgADCgEJAQABLgAECgkJDQANAAAAAA==.Meriam:BAAALgAECgEJAgABLgAFFAMJBQAGAPUQAA==.Merlot:BAAALgAECgcJCAAAAA==.Mesmash:BAABLgAECn8wAAIjAAkJniFHBADjAgAjAAkJniFHBADjAgAAAA==.Metadk:BAAALgAECgQJCAABLgAECggJGQALAGIXAA==.Metahunt:BAAALgAECgIJAgABLgAECggJGQALAGIXAA==.Metamasters:BAAALgAECgQJBgABLgAECggJGQALAGIXAA==.Metatotem:BAAALgAECgIJBAABLgAECggJGQALAGIXAA==.Metavoker:BAAALgAECgUJBQABLgAECggJGQALAGIXAA==.',
Mi='Mialtaa:BAABLgAECn8vAAIMAAkJDxvjCwB2AgAMAAkJDxvjCwB2AgAAAA==.Midgiit:BAAALgAECgUJBQABLgAFFAMJBQAGAPUQAA==.Miink:BAAALgADCgYJBgAAAA==.Milkurs:BAAALgAECgQJBwAAAA==.Miniborg:BAABLgAECn8iAAIFAAkJ+xo5HAB7AgAFAAkJ+xo5HAB7AgABLgAFFAYJGgAOABAeAA==.Minidude:BAAALgAECgYJEAAAAA==.Minionghost:BAAALgADCggJCAAAAA==.Miyuki:BAAALgAECgQJBgAAAA==.Mizzen:BAAALgAFFAEJAQABLgAFFAcJIQAQAKMVAA==.',
Mj='Mjolnir:BAAALgAECgcJBgAAAA==.',
Mo='Moejojojo:BAABLgAECn8WAAILAAkJ0yF4DwBTAgALAAkJ0yF4DwBTAgAAAA==.Monkter:BAABLgAECn8ZAAQLAAgJYheyHADJAQALAAgJYheyHADJAQAXAAEJ/gbfbgAmAAAMAAEJfggUoAAiAAAAAA==.Monsignore:BAAALgADCgQJBAAAAA==.Moofasaha:BAAALgAECgkJEAAAAA==.Mooheals:BAAALgADCgEJAQAAAA==.Moonk:BAAALgAECgcJBQAAAA==.Morangia:BAAALgADCgcJBwAAAA==.Morbus:BAAALgAECgUJBQAAAA==.Morduos:BAAALgAECgcJBgABLgAECggJFQACAAceAA==.Morog:BAACLgAFFH8WAAMmAAYJURpxBQC4AQAmAAYJURpxBQC4AQAFAAEJ0w1tqwBCAAAuAAQKfykABBMACQmpGyMsAM0BABMABgmOHSMsAM0BAAUABgkbGq0/ALABACYABgnqE/UpAFEBAAAA.Morragan:BAAALgAECgQJBQAAAA==.Mortegom:BAAALgADCgcJBwAAAA==.Moráthi:BAAALgADCgcJBwAAAA==.',
Mu='Mulvan:BAAALgAECggJEQAAAA==.',
My='Myinja:BAAALgAECgQJCAABLgAECggJGQALAGIXAA==.Myrddinwyllt:BAAALgAECgYJDAAAAA==.Myzac:BAAALgAECgEJAQAAAA==.',
Mz='Mzharipants:BAAALgADCgIJAgAAAA==.',
Na='Naadra:BAAALgAECgEJAQAAAA==.Nabû:BAAALgADCggJDwAAAA==.Naema:BAAALgAECggJDgAAAA==.Nalid:BAACLgAFFH8TAAIEAAUJJiW2AgCqAQAEAAUJJiW2AgCqAQAuAAQKf0QAAwQACQnAJkAAAIwDAAQACQnAJkAAAIwDAAgAAQmuAl6mABsAAAAA.Nanarus:BAACLgAFFH8TAAIUAAIJPh0zEgCQAAAUAAIJPh0zEgCQAAAuAAQKf1sAAxQACQkuINUAAB0DABQACQkuINUAAB0DABAABgnkA+VWALgAAAAA.Nanosec:BAAALgAECgEJAQAAAA==.Nansea:BAAALgAECgEJAgAAAA==.Nashalie:BAABLgAECn80AAIhAAkJsR4PAwBvAgAhAAkJsR4PAwBvAgAAAA==.Natedawg:BAAALgAECgUJCQAAAA==.',
Ne='Neezzdutzz:BAAALgAECgQJBAAAAA==.Nefele:BAABLgAECn8hAAIBAAkJ5RUWIwA8AgABAAkJ5RUWIwA8AgAAAA==.Nepheli:BAACLgAFFH8GAAICAAMJUxefVgDrAAACAAMJUxefVgDrAAAuAAQKf00AAgIACQlrJF4DAFIDAAIACQlrJF4DAFIDAAAA.Newrhu:BAAALgAECgYJBwAAAA==.Nexbasia:BAACLgAFFH8WAAIEAAMJnRLwBgC/AAAEAAMJnRLwBgC/AAAuAAQKf3oAAwQACQmYH+sAAIICAAQACQmYH+sAAIICAAMAAgn2Apr6ABoAAAAA.',
Ni='Nickyboy:BAABLgAECn8qAAQeAAcJmyLhBQAKAgAeAAcJmyLhBQAKAgAhAAIJvg54BwFhAAAdAAEJrBd0PQA3AAAAAA==.Nightevel:BAAALgAECgUJBQAAAA==.Nihimetal:BAAALgAECgYJCQAAAA==.Nikash:BAABLgAECn80AAMIAAkJFBNVHADnAQAIAAkJFBNVHADnAQADAAYJ+QhgfwC8AAAAAA==.Nisato:BAAALgAECgUJBQAAAA==.',
No='Noctum:BAAALgAECgYJEAAAAA==.Nommei:BAAALgAECgcJEwAAAA==.Northic:BAAALgAECgYJBgABLgAECgkJNQAGAPEgAA==.Nortikolait:BAAALgAECgEJAQABLgAECgkJNQAGAPEgAA==.',
Ny='Nyriah:BAAALgAECgUJCwAAAA==.Nyxys:BAAALgAECgMJAwAAAA==.',
Ob='Obm:BAAALgAECgUJCwAAAA==.',
Oc='Octoface:BAAALgAECgYJBQAAAA==.Octt:BAACLgAFFH8HAAIhAAMJoRntagDuAAAhAAMJoRntagDuAAAuAAQKfyAAAiEACQk5HLkHAJIBACEACQk5HLkHAJIBAAAA.',
Of='Offal:BAABLgAECn82AAQjAAYJjxWvBQAaAQAYAAYJCAsJGAA5AQAjAAYJjxWvBQAaAQAlAAEJJQV2swAjAAAAAA==.',
Ol='Olanna:BAAALgAECgYJDAAAAA==.Oldcannabis:BAAALgAECgQJCwAAAA==.',
Om='Ominis:BAAALgAECgUJCQAAAA==.',
Oo='Oomaw:BAAALgAFFAEJAQAAAA==.',
Or='Orcal:BAACLgAFFH8hAAIkAAYJshT7KQAgAQAkAAYJshT7KQAgAQAuAAQKfx0AAiQACAn7GnQQAHECACQACAn7GnQQAHECAAAA.Ormie:BAAALgAECgQJBAAAAA==.Ornimus:BAABLgAECn8iAAQPAAgJfxODCADUAAAPAAcJWxGDCADUAAAOAAQJEARkKAGJAAASAAIJLgUxGQBGAAAAAA==.Ortian:BAAALgAECgEJAQABLgAECgUJCAANAAAAAA==.',
Ot='Otherrhu:BAAALgAECgYJCAAAAA==.',
Oz='Ozo:BAABLgAECn8dAAIFAAcJqBIgbQBnAQAFAAcJqBIgbQBnAQAAAA==.',
Pa='Paiva:BAAALgAECgYJCQAAAA==.Palandor:BAAALgADCgMJAwAAAA==.Pallyscorned:BAABLgAECn9FAAIPAAkJ/iHjAgD3AgAPAAkJ/iHjAgD3AgAAAA==.Pampas:BAABLgAECn8bAAMBAAkJkgSndAD/AAABAAkJkgSndAD/AAAWAAEJ5AFvwwAZAAAAAA==.Pandamonic:BAAALgAECgQJBAAAAA==.Panduh:BAAALgAECgMJAwABLgAFFAQJEQAGAJ4gAA==.Paxdei:BAAALgAECgUJCQAAAA==.',
Pe='Ped:BAAALgAECgQJBgAAAA==.',
Ph='Phenixy:BAAALgAECgYJDAAAAA==.Phoebell:BAAALgAECgYJDQAAAA==.',
Pi='Pinkducky:BAABLgAECn8nAAIGAAcJ1gesHADJAAAGAAcJ1gesHADJAAAAAA==.',
Pl='Plen:BAACLgAFFH8FAAIGAAMJ9RC+pwDMAAAGAAMJ9RC+pwDMAAAuAAQKfzAAAxwACQnNH5wDAMQBAAYACQmnHFo1AGECABwABgk/IJwDAMQBAAAA.',
Po='Ponder:BAAALgAECgYJCgAAAA==.Poppyseed:BAAALgAECgMJAwAAAA==.Poquads:BAAALgAECgQJCgAAAA==.',
Pr='Priestdoof:BAAALgADCgcJBwAAAA==.Primaris:BAAALgAECgcJDAAAAA==.Prinnce:BAAALgAECgcJDgABLgAECgkJVQALABokAA==.Príestatute:BAAALgAECgUJBQABLgAFFAMJCwAFAAAXAA==.',
Pu='Pulmifinger:BAAALgAECgEJAwAAAA==.Punka:BAAALgAECgEJAQAAAA==.Purplesea:BAAALgADCgcJDQABLgAECgkJOgASAGYTAA==.',
Pv='Pve:BAAALgAECgcJCAAAAA==.',
Py='Pygon:BAAALgAECgIJAgAAAA==.',
Qi='Qilt:BAAALgADCgcJBwAAAA==.',
Qu='Quasar:BAABLgAECn8lAAIiAAkJmBgVQQAZAgAiAAkJmBgVQQAZAgAAAA==.',
Ra='Raaluur:BAAALgAECgQJBwAAAA==.Radra:BAACLgAFFH8HAAMVAAQJ7gNgEgCbAAAVAAQJ7gNgEgCbAAACAAEJuQF1YAAdAAAuAAQKf0gABBUACQlvFI8FAHEBABUACQkKFI8FAHEBABEABwnEDVgDACUBAAIABglXCX4dAJoAAAAA.Radras:BAAALgAECgcJCQAAAA==.Raeku:BAABLgAECn8tAAImAAkJkCAUBgDCAgAmAAkJkCAUBgDCAgAAAA==.Rainee:BAAALgADCgYJBwAAAA==.Raja:BAAALgAECgUJDwAAAA==.Rathalo:BAAALgAECgQJBgAAAA==.Rav:BAAALgADCgUJBQAAAA==.Ravick:BAAALgADCgEJAQAAAA==.Razensetral:BAAALgAECggJCAAAAA==.Razzlor:BAAALgADCgUJBQAAAA==.',
Re='Reducto:BAABLgAECn8hAAMRAAYJhRXmFwDiAAACAAYJnBNxfgAjAQARAAUJPxXmFwDiAAAAAA==.Reenailinefh:BAAALgADCgcJDgAAAA==.Relitha:BAAALgADCgUJCQAAAA==.Remeii:BAABLgAECn8iAAMBAAgJJghPgADgAAABAAcJtgRPgADgAAAWAAYJUQP9cQCVAAAAAA==.Retribution:BAABLgAECn85AAIOAAkJ5hM9SADtAQAOAAkJ5hM9SADtAQAAAA==.Reylexgt:BAAALgAECgEJAQAAAA==.',
Rh='Rhaenera:BAAALgAECgMJCgABLgAECgkJVQALABokAA==.Rhage:BAAALgADCgkJCQAAAA==.',
Ri='Richcraniums:BAAALgADCgcJBwAAAA==.Rivkah:BAAALgAECgEJAQAAAA==.',
Ro='Roachers:BAAALgADCgIJAgAAAA==.Robomurph:BAAALgADCggJDwAAAA==.Rolas:BAAALgAECgYJAgAAAA==.Ronfax:BAACLgAFFH85AAMBAAgJQCOiAAA2AwABAAgJQCOiAAA2AwAWAAMJKw5uLABbAAAuAAQKfywAAwEACQm2IzwFAF8DAAEACQm2IzwFAF8DABYABgmeHN8qAJwBAAAA.Ronia:BAAALgADCgIJAgABLgAECggJGwACAMMYAA==.Rooss:BAAALgAECgcJEgAAAA==.Roqane:BAAALgAECgQJBAAAAA==.Roserade:BAABLgAECn8UAAMcAAkJQxSKHwBYAQAcAAkJ5xOKHwBYAQAHAAEJ+AyqPAAtAAAAAA==.Rothkin:BAAALgADCgMJAwAAAA==.Rotreiter:BAAALgADCgEJAQAAAA==.Rowdyredneck:BAAALgADCgMJAwABLgAECggJGQALAGIXAA==.',
Ru='Rukea:BAAALgAECgQJBAAAAA==.Rul:BAAALgAFFAEJAQABLgAFFAQJEQAGAJ4gAA==.',
Ry='Ryllae:BAAALgAECgQJBQABLgAECgkJHgAVAFciAA==.Ryuusythe:BAAALgADCgcJBwAAAA==.Ryân:BAAALgADCgEJAQAAAA==.',
['Rì']='Rììdìì:BAACLgAFFH8GAAIdAAMJtgclBwC0AAAdAAMJtgclBwC0AAAuAAQKfxQAAh0ABwnxFFkCAIwBAB0ABwnxFFkCAIwBAAEuAAUUAwkLAAUAABcA.',
Sa='Saara:BAAALgADCgEJAQAAAA==.Sackhammer:BAAALgAECgQJBAAAAA==.Saint:BAAALgAECgkJDwAAAA==.Salopard:BAAALgAECgIJAgAAAA==.Samson:BAABLgAECn8YAAQLAAcJKxzRIgCaAQALAAYJLRzRIgCaAQAMAAUJtxHfTgDFAAAXAAIJ3wpgqgBJAAABLgAECgUJCwANAAAAAA==.Sanivan:BAABLgAECn8VAAIVAAcJ+hdxGgDvAQAVAAcJ+hdxGgDvAQAAAA==.Sanoan:BAAALgAECgQJBQAAAA==.Saori:BAAALgAECgEJAQAAAA==.Sappy:BAABLgAECn8aAAQgAAcJdR9BCQCuAQAgAAYJsh5BCQCuAQAKAAQJrxwzOwA/AQAnAAQJ8BLcCQDFAAABLgAFFAQJEQAGAJ4gAA==.Sarinae:BAABLgAECn8qAAQkAAkJeAe0DAClAAAkAAgJzwW0DAClAAAfAAEJGQ7DCQAtAAAZAAEJwAEQRAAfAAAAAA==.Sarmuc:BAABLgAECn8dAAMaAAkJtxYVAwCBAQAaAAkJtxYVAwCBAQAWAAEJXwuesAAoAAAAAA==.Sarnluz:BAAALgAECgEJAQABLgAECggJEQANAAAAAA==.Saryda:BAAALgAECgYJDgABLgAECgcJCAANAAAAAA==.Sauda:BAAALgAECgMJBAAAAA==.Saurian:BAAALgADCgEJAQAAAA==.',
Sc='Schadoww:BAAALgAECggJDQABLgAFFAMJBQAGAPUQAA==.Scubagal:BAAALgAECgYJDQAAAA==.Scy:BAAALgAECggJDgAAAA==.Scythraza:BAABLgAECn8/AAMkAAgJTBtKAgDhAQAkAAgJTBtKAgDhAQAZAAIJTw7fCwBHAAAAAA==.',
Se='Seablue:BAAALgAECgMJBQABLgAECgkJOgASAGYTAA==.Sedaleice:BAAALgAECgEJAQAAAA==.Sedge:BAAALgADCgEJAQAAAA==.Seedsprayer:BAAALgAECgYJDAAAAA==.Selara:BAAALgAECgMJAwAAAA==.Sellenah:BAABLgAECn8bAAICAAgJwxjOXAByAQACAAgJwxjOXAByAQAAAA==.Sensu:BAAALgAECgcJEwAAAA==.Sensual:BAAALgAECgYJAwAAAA==.Sernian:BAABLgAFFH8IAAIFAAQJWBR1JAARAQAFAAQJWBR1JAARAQABLgAFFAUJHwAOAPgjAA==.Seä:BAABLgAECn86AAISAAkJZhMXHAAjAgASAAkJZhMXHAAjAgAAAA==.',
Sh='Shadoweave:BAABLgAECn8dAAIQAAkJqwfcMwBJAQAQAAkJqwfcMwBJAQAAAA==.Shampooshady:BAAALgAECgMJBAAAAA==.Shamtea:BAACLgAFFH8KAAIWAAMJvwjMIACcAAAWAAMJvwjMIACcAAAuAAQKfzYAAhYACQkmFE0GAHwBABYACQkmFE0GAHwBAAAA.Shandrin:BAAALgAECgIJAgAAAA==.Shapzan:BAABLgAECn8ZAAMIAAgJfRYhLwBjAQAIAAgJfRYhLwBjAQAbAAUJ3g3oDQCcAAAAAA==.Shareliss:BAAALgADCgYJBgAAAA==.Sharks:BAAALgAECgQJDwAAAA==.Shiik:BAAALgAECgYJBwABLgAECgcJGQASABIYAA==.Shivant:BAACLgAFFH8FAAIBAAMJ7goPMQCDAAABAAMJ7goPMQCDAAAuAAQKfzoAAwEACQlJHa0VAJ0CAAEACQlJHa0VAJ0CABYAAglDBZ6bAEEAAAAA.Shmeegleroop:BAAALgAECgYJDgAAAA==.Shroomhunter:BAAALgAECgEJAQAAAA==.Shîvå:BAACLgAFFH8IAAIRAAMJ6SFlAwAEAQARAAMJ6SFlAwAEAQAuAAQKfzEAAhEACQniID0CAOQCABEACQniID0CAOQCAAAA.',
Si='Sideburns:BAAALgAECgMJAwAAAA==.Silvertime:BAAALgADCgYJBwAAAA==.Sindice:BAAALgAECgYJCwABLgAFFAgJOQABAEAjAA==.',
Sk='Skaa:BAAALgAECgEJAwAAAA==.',
Sl='Slammy:BAAALgAECgQJBAAAAA==.Slanesh:BAAALgAECgIJAgAAAA==.Slimpooshady:BAACLgAFFH8MAAIbAAMJvQy4FQB5AAAbAAMJvQy4FQB5AAAuAAQKfzQAAwMACQkWEn0oAA4CAAMACQkWEn0oAA4CABsACQmmEzcRANgBAAAA.Sloth:BAABLgAECn87AAIcAAkJICEyAQDHAgAcAAkJICEyAQDHAgAAAA==.',
So='Solaspirus:BAABLgAECn8uAAMCAAkJ6BsEJAA/AgACAAkJ6BsEJAA/AgARAAEJawxCNwAqAAAAAA==.Solinius:BAAALgAECgQJBQAAAA==.Sope:BAAALgAECgYJDQABLgAECggJDgANAAAAAA==.Sorhtx:BAAALgAECgUJBwAAAA==.Sostoned:BAAALgAECgEJAQABLgAECgkJNAAgAPEcAA==.Soulomatic:BAAALgADCgcJBwAAAA==.',
Sp='Spectors:BAACLgAFFH8HAAIdAAMJjQVZBwCwAAAdAAMJjQVZBwCwAAAuAAQKf0gAAx0ACAmMEooDAD8BAB0ABwkcFYoDAD8BACEABwnnA3DBAMoAAAAA.Spekturx:BAAALgAECgEJAQAAAA==.Spideygirl:BAABLgAECn8WAAISAAgJPxzPEQCFAgASAAgJPxzPEQCFAgAAAA==.Sprayinnseed:BAAALgAECgMJBAAAAA==.Sprayinseed:BAAALgADCgMJAwAAAA==.',
Sq='Squarepants:BAAALgAECgQJCQABLgAECgQJDwANAAAAAA==.',
St='Stabon:BAABLgAECn8lAAIKAAkJcwlDHwCcAQAKAAkJcwlDHwCcAQAAAA==.Stalaediir:BAAALgADCgQJBAAAAA==.Stardre:BAAALgADCgQJBQAAAA==.Stevesmith:BAAALgAECgEJAgAAAA==.Stonedrage:BAAALgADCgEJAQAAAA==.Stormspirits:BAAALgADCgUJBQAAAA==.Sturdyy:BAAALgADCgMJAwAAAA==.Stãrkïllér:BAAALgADCgMJAwAAAA==.',
Su='Sugarmarks:BAAALgAECgYJDwAAAA==.',
Sw='Sweetstorm:BAABLgAECn92AAIVAAkJ8g34BQBgAQAVAAkJ8g34BQBgAQAAAA==.',
Sy='Synvara:BAAALgADCgUJBQAAAA==.',
['Sê']='Sêphiroth:BAABLgAECn83AAISAAkJWxeEFABqAgASAAkJWxeEFABqAgAAAA==.',
Ta='Taekoad:BAAALgADCgIJAgAAAA==.Tahlia:BAAALgAECgEJAQAAAA==.Tania:BAABLgAECn8aAAIOAAgJsxMTXwCzAQAOAAgJsxMTXwCzAQAAAA==.Taredelaria:BAAALgAECgEJAwAAAA==.Tarixx:BAABLgAFFH8GAAMOAAMJ/w5hJACjAAAOAAIJQg5hJACjAAAPAAEJeRA0GgAqAAAAAA==.Tazanoth:BAACLgAFFH8IAAQFAAMJBBLAcQC8AAAFAAMJ0Q/AcQC8AAAmAAIJKQ7lKwCDAAATAAEJTArEJgBPAAAuAAQKfyEAAyYACQmaG4kPADYCACYACQmQGokPADYCABMABglBGtYwALABAAAA.',
Te='Teasa:BAACLgAFFH8MAAIFAAMJHw2rNADRAAAFAAMJHw2rNADRAAAuAAQKf0IAAgUACQnZGYohAF8CAAUACQnZGYohAF8CAAAA.Tekeela:BAAALgAECgYJCgABLgAFFAcJEwAFAN8VAA==.Tekeelà:BAACLgAFFH8TAAQFAAcJ3xVDAgB7AQAFAAcJ3xVDAgB7AQATAAEJVgAiLgA1AAAmAAEJhAF0OAAqAAAuAAQKfzMABAUACQmJIaMVAIoCAAUACQkHH6MVAIoCACYACQn8Gp8PADUCABMABwm3EeY5AHoBAAAA.Tekkamaki:BAAALgADCgcJCAAAAA==.',
Th='Thalion:BAABLgAECn8gAAMFAAYJ0ATrMQB7AAAFAAYJ0ATrMQB7AAAmAAUJcgF+VQBXAAAAAA==.Theenna:BAABLgAECn8XAAMhAAgJ3AmMFQDAAAAhAAcJYgeMFQDAAAAeAAQJuQvwCACeAAAAAA==.Thetodd:BAAALgAECgIJAgAAAA==.Thianna:BAABLgAECn8pAAMSAAkJyBn5GwAkAgASAAkJyBn5GwAkAgAOAAgJdRJKHQDnAAAAAA==.Thiculuskage:BAABLgAECn8YAAISAAkJvB77BwAMAwASAAkJvB77BwAMAwAAAA==.Thinkso:BAAALgADCgcJGwAAAA==.Thobu:BAAALgAECgcJCwAAAA==.Thodos:BAAALgADCgEJAQAAAA==.Thornscale:BAABLgAECn9OAAQkAAkJ3ho3EQBcAgAkAAkJ3ho3EQBcAgAfAAYJbhYpAgAvAQAZAAYJogvrKAAsAQAAAA==.Thorrent:BAAALgADCgcJDQAAAA==.',
Ti='Tigolcrittys:BAAALgAECgcJEgABLgAFFAMJCwAFAAAXAA==.Timeforloads:BAABLgAECn8rAAMIAAkJ8hYdNABIAQAIAAcJOhUdNABIAQADAAYJxB9UCAA3AQAAAA==.Tirria:BAAALgAECgYJCQAAAA==.',
To='Tolk:BAAALgAECgcJEQAAAA==.Tomzombe:BAAALgAECgQJBgAAAA==.Totem:BAABLgAECn8WAAIWAAgJvQu3RQAdAQAWAAgJvQu3RQAdAQAAAA==.Totenz:BAAALgADCgYJBgAAAA==.Tovê:BAAALgAECggJCAAAAA==.',
Tr='Traveler:BAAALgAECgIJAgAAAA==.Trickyflamom:BAABLgAECn8aAAIiAAcJzBwnCgC2AQAiAAcJzBwnCgC2AQABLgAFFAQJIgAiAPYaAA==.Troloq:BAABLgAECn85AAQdAAkJfx2BCADgAQAhAAgJHhuKNwD7AQAdAAgJWReBCADgAQAeAAYJTRoEFAAQAQAAAA==.Trondoom:BAAALgADCgYJBgAAAA==.',
Tu='Tugboattimmy:BAAALgAECgEJAQAAAA==.Tulisha:BAAALgAECgUJCgAAAA==.Turero:BAABLgAECn8WAAISAAcJkAdyCgD+AAASAAcJkAdyCgD+AAABLgAFFAQJGAADAEIRAA==.Turger:BAAALgAECgUJCAABLgAECgkJEAANAAAAAA==.Turinnii:BAAALgADCgcJBwAAAA==.',
Ul='Uller:BAABLgAECn8oAAIiAAkJDhrQMABWAgAiAAkJDhrQMABWAgAAAA==.',
Um='Umbrafang:BAAALgAECgEJBAAAAA==.',
Un='Unholyspirit:BAAALgAECgQJDwAAAA==.',
Va='Vahlorraa:BAABLgAECn8oAAMSAAgJGw9gBwBRAQASAAcJMhBgBwBRAQAOAAEJdAMOcwATAAAAAA==.Vaimei:BAACLgAFFH8GAAIhAAMJQBW2MQDFAAAhAAMJQBW2MQDFAAAuAAQKfz0AAx4ACQlBIy8CAKICAB4ACAk9Iy8CAKICACEACAlhID8WAJ8CAAAA.Valashune:BAAALgADCgEJAQAAAA==.Valsilla:BAAALgAECgYJBgABLgAECgkJHgAVAFciAA==.Vapor:BAABLgAECn80AAIgAAkJ8RyPAABeAgAgAAkJ8RyPAABeAgAAAA==.Varaine:BAAALgAECgIJAgAAAA==.Varanius:BAAALgAECgEJAgAAAA==.',
Ve='Veebes:BAAALgAECggJCAAAAA==.Veebs:BAABLgAECn8rAAMlAAgJSBrhAgAgAgAlAAgJSBrhAgAgAgAjAAEJAAAySAAuAAAAAA==.Velóran:BAAALgADCgcJBwAAAA==.Vendola:BAABLgAECn8gAAIiAAgJaQboqgAqAQAiAAgJaQboqgAqAQAAAA==.Vento:BAABLgAECn8VAAIGAAgJjxWuYgCjAQAGAAgJjxWuYgCjAQAAAA==.Verité:BAABLgAECn8UAAMfAAgJ8gwzDwAXAQAfAAcJdg4zDwAXAQAkAAcJfQmBTgD0AAAAAA==.Veterpeinss:BAAALgADCggJDgAAAA==.',
Vi='Viento:BAAALgADCgcJBwAAAA==.Villiveil:BAAALgAECgEJAQABLgAFFAQJBgAOAJoZAA==.Vintersorg:BAAALgAECgUJCQAAAA==.Virauca:BAABLgAECn9OAAICAAkJjhYtLgAOAgACAAkJjhYtLgAOAgAAAA==.Viuhl:BAAALgADCgQJAwAAAA==.',
Vo='Vodgrax:BAAALgAECgIJAgAAAA==.Voidstar:BAAALgAECgUJDAAAAA==.Voltimand:BAAALgAECgEJAQABLgAFFAMJCgABAGcPAA==.',
Vv='Vvicked:BAABLgAECn8gAAIGAAgJrCI8FwC7AgAGAAgJrCI8FwC7AgAAAA==.',
Vy='Vynesta:BAABLgAECn8eAAIVAAkJVyKvAwAZAwAVAAkJVyKvAwAZAwAAAA==.',
Wa='Wala:BAAALgAECgcJDAAAAA==.Wamoo:BAAALgAECgEJAgAAAA==.Wanagi:BAAALgAECgUJBgAAAA==.Wankz:BAAALgAECgkJEgAAAA==.Wankzerkin:BAAALgADCgEJAQAAAA==.Warriorguyes:BAABLgAECn8fAAIlAAkJtSKbBwDlAgAlAAkJtSKbBwDlAgAAAA==.',
We='Weyna:BAABLgAECn84AAMXAAgJ3hHVMgCsAQAXAAgJ3hHVMgCsAQAMAAYJVAmnTQDJAAABLgAFFAYJHwAZAO8UAA==.',
Wh='Whisperingei:BAAALgAECgYJCgAAAA==.Whomper:BAABLgAECn8dAAMbAAcJgRL8CADzAAAbAAUJkxX8CADzAAAEAAcJZQkvCAC4AAAAAA==.Whpheonix:BAAALgADCgkJEAAAAA==.',
Wi='Wickedshadow:BAAALgAECgMJAwAAAA==.Widowx:BAACLgAFFH8JAAMWAAMJaw+MHwCjAAAWAAMJaw+MHwCjAAABAAEJEgEjjwAgAAAuAAQKfzUAAhYACQlGHckDAPEBABYACQlGHckDAPEBAAAA.Winfurdal:BAAALgADCggJCAAAAA==.',
Wo='Womphunt:BAABLgAECn8WAAIFAAcJlBqgPgDnAQAFAAcJlBqgPgDnAQABLgAECgkJLAAUABkhAA==.',
Wr='Wrandohunt:BAAALgAECgEJBAAAAA==.Wrandowdemon:BAAALgADCgcJBwAAAA==.Wreckitrandy:BAAALgAECgEJAQAAAA==.Wryn:BAAALgAECgkJEQABLgAFFAMJBQAGAPUQAA==.',
Wu='Wulyn:BAAALgAECgcJDwAAAA==.',
Wy='Wylla:BAABLgAECn8YAAILAAcJvQ8gBgA0AQALAAcJvQ8gBgA0AQAAAA==.',
Xa='Xalethra:BAABLgAECn89AAICAAkJ8CQ7BQA0AwACAAkJ8CQ7BQA0AwAAAA==.Xaltheris:BAAALgAECgUJBgAAAA==.',
Xe='Xelha:BAAALgAECgYJBgAAAA==.Xenophobias:BAABLgAECn8aAAMcAAcJyBGTBwAEAQAcAAcJyBGTBwAEAQAGAAIJUgMdowEdAAAAAA==.',
Xh='Xhosen:BAABLgAFFH8HAAIGAAIJEhJhbAB8AAAGAAIJEhJhbAB8AAAAAA==.',
Xr='Xratedmurdaa:BAAALgAECgEJAQAAAA==.',
Xs='Xsuns:BAABLgAECn9JAAIDAAkJYxqqHQBZAgADAAkJYxqqHQBZAgAAAA==.',
Ya='Yarloon:BAAALgADCgcJBwAAAA==.',
Yo='Yodapan:BAAALgADCgkJEgABLgAECgkJFwAIADcLAA==.',
Yt='Ytsirk:BAAALgADCgYJBgAAAA==.',
Yv='Yve:BAAALgAECgUJDQAAAA==.',
Za='Zaharian:BAAALgAECgEJAgAAAA==.Zalajin:BAAALgAECgUJCQAAAA==.Zalila:BAAALgADCgYJBgAAAA==.Zanasi:BAEALgAECggJDgABLgAFFAUJFAAFABQiAA==.Zarayndia:BAAALgAECgYJCAAAAA==.',
Ze='Zeddicus:BAABLgAECn8tAAMdAAkJ9wi2DgBwAQAdAAkJfAi2DgBwAQAhAAUJDgXk8gB8AAAAAA==.Zendragan:BAACLgAFFH8HAAIXAAMJzxAbQQCfAAAXAAMJzxAbQQCfAAAuAAQKfx4AAhcACQlOGOcXAFkCABcACQlOGOcXAFkCAAEuAAUUAwkKAAkAsxEA.Zerhas:BAAALgAECgEJAwAAAA==.',
Zo='Zoe:BAAALgAECgQJCQAAAA==.Zoidz:BAAALgAECggJDAAAAA==.Zombiemagic:BAAALgADCgMJAwAAAA==.Zombruh:BAAALgAECgEJAQAAAA==.Zomgimlothar:BAAALgADCgIJAwAAAA==.Zoomy:BAAALgAECgQJCwAAAA==.',
Zy='Zyntarum:BAAALgADCgEJAQAAAA==.Zythopoios:BAAALgAFFAEJAgAAAA==.',
Zz='Zzilladi:BAABLgAFFH8SAAMUAAYJ1RkTCQC8AQAUAAYJ1RkTCQC8AQAQAAEJAACzRAAAAAAAAA==.Zzilladinzz:BAACLgAFFH8UAAIOAAUJjSBuMQBOAQAOAAUJjSBuMQBOAQAuAAQKfyIAAg4ACQkIIwsSAAIDAA4ACQkIIwsSAAIDAAAA.',
['Äm']='Ämmærthëf:BAAALgAECgEJAQAAAA==.',
['Ëu']='Ëulogy:BAAALgAECgcJEQABLgAFFAMJCAARAOkhAA==.',
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
