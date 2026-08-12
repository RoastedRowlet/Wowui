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
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=46,date='2026-08-11',data={Aa='Aarmorr:BAABLgAECn9SAAIBAAkJmhk4FgCYAgABAAkJmhk4FgCYAgAAAA==.Aatus:BAAALgAECgcJDQAAAA==.',
Ab='Absoul:BAAALgAECgQJBwAAAA==.Abyssidia:BAAALgAECgMJAwAAAA==.',
Ac='Acinianis:BAAALgAECgEJAQAAAA==.Acinthos:BAAALgAECgQJBgAAAA==.',
Ad='Addah:BAAALgAECgQJBwAAAA==.Adiros:BAAALgADCgUJBQAAAA==.',
Ae='Aechelus:BAAALgADCgEJAQABLgAECggJFQACAAceAA==.Aedelas:BAAALgAECgIJBAAAAA==.Aeloriá:BAABLgAECn9PAAMDAAkJyCBxBwBAAwADAAkJyCBxBwBAAwAEAAEJFQGgOwAPAAAAAA==.Aelyra:BAAALgAECggJEgAAAA==.',
Ag='Agrosa:BAAALgAECgYJBgAAAA==.',
Ai='Aimeeiove:BAAALgAECgYJCgAAAA==.Airad:BAAALgADCgUJBgAAAA==.Airoldeel:BAAALgAECgIJAgAAAA==.',
Al='Alcarza:BAAALgAECgMJCAAAAA==.Alchon:BAABLgAECn8kAAIFAAkJ6xqGLwAeAgAFAAkJ6xqGLwAeAgAAAA==.Aldera:BAABLgAECn88AAIBAAkJwgmxEAAnAQABAAkJwgmxEAAnAQAAAA==.Aledish:BAAALgAECgEJAgAAAA==.Alexstrayza:BAAALgAECgMJAwAAAA==.Alicien:BAABLgAECn8jAAMGAAkJwRwpSADqAQAGAAkJwRwpSADqAQAHAAEJyhBgFgA3AAAAAA==.Alista:BAAALgAECgYJCwAAAA==.Alladon:BAAALgADCgUJBQAAAA==.Allykat:BAABLgAECn9QAAMDAAgJRxmjAwAUAgADAAgJRxmjAwAUAgAIAAYJRxEIPwATAQAAAA==.Alorris:BAAALgAECgQJBgABLgAECgkJGQAJAFggAA==.Alunathsong:BAAALgADCgcJBwAAAA==.Alvagíngras:BAAALgAECgkJEAAAAA==.Alyra:BAAALgAECgYJBgAAAA==.',
Am='Amaith:BAACLgAFFH8KAAIKAAIJUw/AHgCNAAAKAAIJUw/AHgCNAAAuAAQKfyMAAgoACQmnG0ABAJoCAAoACQmnG0ABAJoCAAAA.Amantillado:BAAALgAECgUJCAABLgAECggJGQALAGIXAA==.Amata:BAAALgAECgUJCwAAAA==.Amelianne:BAAALgAECgcJEQAAAA==.Amiria:BAAALgAECgYJBgAAAA==.Ammastary:BAAALgAECgUJBwAAAA==.Ammonfrey:BAAALgAECgEJAQAAAA==.Amorfati:BAAALgAECgEJAQAAAA==.',
An='Ananiel:BAAALgADCgQJBQABLgAECgkJLwAMAA8bAA==.Andragos:BAAALgAECgQJCgAAAA==.Andrea:BAABLgAECn9KAAIEAAkJYR3oBACrAgAEAAkJYR3oBACrAgAAAA==.Andrelia:BAAALgAECgMJAwAAAA==.Angelec:BAAALgAECgEJAQAAAA==.Angelex:BAAALgAECgEJAQAAAA==.Anthria:BAAALgAECgcJEAAAAA==.',
Ao='Aoon:BAAALgAECgEJAQAAAA==.',
Ap='Apoleth:BAAALgADCgMJAwAAAA==.',
Aq='Aqules:BAAALgADCgEJAgAAAA==.',
Ar='Arand:BAAALgADCgIJAwAAAA==.Arcapeligo:BAAALgAECgEJAgAAAA==.Archonsfury:BAAALgAECggJDwAAAA==.Arilyn:BAAALgAECgMJAwAAAA==.Array:BAAALgAECgUJBQAAAA==.',
As='Asath:BAAALgAECgYJDAAAAA==.Ascended:BAAALgAECgEJAgABLgADCgkJCQANAAAAAA==.Asheye:BAAALgAECgkJCwABLgAFFAMJBQAGAPUQAA==.Ashogar:BAAALgAECgUJBQAAAA==.Ashuranadi:BAAALgADCgcJBwAAAA==.Askir:BAAALgADCgMJAwAAAA==.Asnew:BAAALgAECgkJEQAAAA==.Asura:BAAALgAECgkJEwAAAA==.Asyllaa:BAABLgAECn8eAAMOAAkJFx+LLABPAgAOAAcJOyOLLABPAgAPAAYJ9hLNHwAWAQAAAA==.',
At='Athelstan:BAAALgADCgIJAgAAAA==.Atnawuerus:BAAALgAECgEJAQAAAA==.Atonement:BAABLgAECn8aAAMJAAkJJBqFFAA5AgAJAAgJNh2FFAA5AgAQAAQJLgkTcwBbAAABLgAFFAMJCAARAOkhAA==.',
Au='Aumaril:BAABLgAECn8mAAMSAAgJ4hepAwD7AQASAAgJ4hepAwD7AQAOAAgJBxnaEgBLAQAAAA==.Auralynn:BAABLgAECn8rAAIOAAkJEAp/kgBOAQAOAAkJEAp/kgBOAQAAAA==.',
Av='Avathar:BAAALgAECgMJBgAAAA==.Averina:BAAALgAECgMJAwAAAA==.Averus:BAABLgAECn9SAAIIAAkJuhLJHQDaAQAIAAkJuhLJHQDaAQAAAA==.',
Az='Azariel:BAABLgAECn8+AAIOAAkJ5BPmUwDOAQAOAAkJ5BPmUwDOAQAAAA==.Azenwraith:BAAALgADCgkJCQAAAA==.Azuriah:BAABLgAECn9MAAMPAAkJ6B3/BQCLAgAPAAkJIB3/BQCLAgAOAAEJXyHCTgFfAAAAAA==.',
Ba='Baane:BAAALgAECgUJCAABLgAECggJFAAJACANAA==.Babnik:BAEBLgAECn8YAAMFAAkJZBNPFQA4AQAFAAkJZBNPFQA4AQATAAIJPw0IMABYAAAAAA==.Bagel:BAACLgAFFH8eAAMSAAUJHCNeDQDhAQASAAUJHCNeDQDhAQAOAAQJaQcxPACrAAAuAAQKfxkAAxIACAmCH1AmAPYBABIACAmCH1AmAPYBAA4AAQnkCrKpASsAAAAA.Baldwin:BAAALgAECgUJBQAAAA==.Ballbreaker:BAAALgAECgQJBAAAAA==.Baminenherb:BAAALgADCgUJBQAAAA==.Bazluz:BAAALgADCgIJAwAAAA==.',
Be='Bearbone:BAAALgAECgIJAwAAAA==.Bearlysoberr:BAAALgAECgUJBQAAAA==.Bedhead:BAABLgAECn9DAAQJAAkJpRdwEQBdAgAJAAkJ7BZwEQBdAgAUAAMJFBx6VQDgAAAQAAEJKwrXjgAsAAAAAA==.Bedrocked:BAAALgAECgIJAwAAAA==.Belaim:BAAALgAECgIJAgAAAA==.Belovis:BAACLgAFFH8fAAIOAAYJiCS1GQCkAQAOAAYJiCS1GQCkAQAuAAQKfyYAAg4ACQk0JOgMACYDAA4ACQk0JOgMACYDAAAA.Berathor:BAAALgAECgkJEwAAAA==.Betsea:BAAALgAECgUJBQABLgAECgkJOgASAGYTAA==.',
Bi='Bidoof:BAABLgAECn86AAIVAAkJvBF2BQCIAQAVAAkJvBF2BQCIAQAAAA==.Bigblunt:BAAALgADCgcJEgAAAA==.Bigear:BAAALgAECgQJBAAAAA==.Bigjohnii:BAAALgADCgcJBwAAAA==.Birdi:BAAALgAECgEJAwAAAA==.Bitemarks:BAAALgADCgcJDgAAAA==.',
Bl='Blackcoat:BAAALgAECgYJDwAAAA==.Bluedragan:BAAALgAECgQJBAABLgAFFAMJCgAJALMRAA==.',
Bo='Boggrog:BAAALgAECgYJCQABLgAECgUJCwANAAAAAA==.Boghamut:BAAALgADCgcJBwABLgAECgUJCwANAAAAAA==.Bolz:BAAALgAECgMJAwAAAA==.Boosch:BAAALgADCgIJAgAAAA==.Boras:BAAALgAECgEJAQABLgAECggJGwACAMMYAA==.Bosshog:BAABLgAECn80AAIWAAkJpAvuNgBeAQAWAAkJpAvuNgBeAQAAAA==.Bowgobrr:BAABLgAECn8qAAMTAAgJ4xXlDgBvAQATAAgJ4xXlDgBvAQAFAAYJ2QpW3QCTAAABLgAFFAkJPgAFADQYAA==.',
Br='Braelyne:BAABLgAECn8WAAIOAAYJdR3JXwDEAQAOAAYJdR3JXwDEAQAAAA==.Brasnite:BAAALgADCgEJAQAAAA==.Brewrock:BAAALgAECgQJCAAAAA==.Brewtilus:BAAALgAECgQJBwAAAA==.Brolaf:BAAALgAECgUJBQAAAA==.Broseidon:BAAALgAECgcJEQAAAA==.Bryst:BAAALgADCgQJBAAAAA==.',
Bu='Buffsalot:BAAALgAECgUJDgAAAA==.Buffwarlock:BAAALgAECgcJBwAAAA==.Bullbatoo:BAAALgAECgEJAQAAAA==.Burlycheeks:BAABLgAECn85AAIOAAkJPCCTGACwAgAOAAkJPCCTGACwAgAAAA==.',
Ca='Calav:BAAALgAECgYJDAAAAA==.Caliista:BAAALgADCggJCAAAAA==.Carlitocool:BAAALgADCgIJAgAAAA==.Carraxus:BAAALgAECgQJDAAAAA==.Cassidyn:BAAALgADCgcJCAAAAA==.Castle:BAABLgAECn8aAAMOAAgJ1h09bwCQAQAOAAcJbhw9bwCQAQASAAYJZwktDgDJAAAAAA==.Catsinhats:BAAALgAECgUJBAABLgAFFAQJFAAGAC8OAA==.Catsneverdie:BAAALgAFFAEJAQABLgAFFAQJFAAGAC8OAA==.Catzinhatz:BAABLgAECn8YAAICAAcJAgq/jgADAQACAAcJAgq/jgADAQABLgAFFAQJFAAGAC8OAA==.',
Ce='Cecelya:BAABLgAECn9AAAQUAAkJ5RlLFwAUAgAUAAkJ5RlLFwAUAgAQAAcJNhGCNABGAQAJAAMJUw1iXACOAAAAAA==.Celerian:BAAALgAECgQJBAAAAA==.Celibate:BAAALgAECgUJBgAAAA==.Celothor:BAAALgADCgYJBgAAAA==.Celticmoon:BAAALgADCgQJBAAAAA==.',
Ch='Cherlia:BAABLgAECn8cAAIWAAYJIhO2RQAyAQAWAAYJIhO2RQAyAQABLgAECgkJHgAVAFciAA==.Chillykiller:BAAALgAECgYJBwABLgAECgkJHgAVAFciAA==.Chiva:BAAALgAECgQJBAABLgAFFAMJBwABAGAPAA==.Chivactdl:BAAALgAECgMJBAABLgAFFAMJBwABAGAPAA==.Chivalt:BAAALgAECgEJAQABLgAFFAMJBwABAGAPAA==.Chonch:BAAALgAECgIJAgAAAA==.Chozen:BAAALgAECggJCwAAAA==.Chunknoriss:BAABLgAECn8vAAMXAAYJYiD3HQApAgAXAAYJYiD3HQApAgALAAMJWwWbdwBhAAABLgAFFAMJBwABAGAPAA==.',
Ci='Cigarettes:BAABLgAECn8XAAIYAAYJsRWlBwDyAAAYAAYJsRWlBwDyAAAAAA==.',
Cl='Claudiuss:BAAALgAECgYJDAABLgAFFAMJCgABAGcPAA==.Clurefu:BAABLgAECn84AAMXAAkJvCEQBQBaAwAXAAkJvCEQBQBaAwALAAMJ5BZVWACuAAABLgAFFAMJDQADAK8dAA==.Clurelock:BAACLgAFFH8NAAIDAAMJrx1AEgD7AAADAAMJrx1AEgD7AAAuAAQKf0AAAgMACQn6Ii4EAHsDAAMACQn6Ii4EAHsDAAAA.Cluremage:BAAALgAECgYJEQAAAA==.Clurethyr:BAABLgAECn8rAAIZAAgJzB+KAADZAgAZAAgJzB+KAADZAgABLgAFFAMJDQADAK8dAA==.',
Co='Cobblestone:BAAALgAECgIJAgAAAA==.Codenameknd:BAAALgAECgIJAgAAAA==.Comsuck:BAAALgAECgcJEQAAAA==.Conchobhar:BAABLgAECn8VAAIXAAkJlBoMGgBHAgAXAAkJlBoMGgBHAgAAAA==.Constella:BAAALgADCgYJCQAAAA==.Coppertan:BAAALgAECgMJBQAAAA==.Coralyne:BAAALgADCgEJAQAAAA==.Corrosion:BAABLgAECn8wAAIaAAkJUx5aAQAzAgAaAAkJUx5aAQAzAgAAAA==.',
Cr='Crazyshammy:BAAALgAECgkJEgAAAA==.Crommash:BAAALgAECgcJCgAAAA==.Crono:BAAALgAECgQJCQAAAA==.Crunchynuget:BAABLgAECn8pAAIOAAkJbSApBACaAgAOAAkJbSApBACaAgABLgAFFAcJGwAOAK0dAA==.',
Ct='Cthuwu:BAAALgAECgMJAwABLgAFFAcJFAAFAN8VAA==.',
Cu='Cujotaro:BAAALgAECgEJAgAAAA==.Cumberdale:BAAALgAECgUJBQAAAA==.',
Cv='Cvhamster:BAAALgAECgQJCgAAAA==.',
Cy='Cybeast:BAABLgAECn81AAMEAAkJkh54BAC4AgAEAAkJhB54BAC4AgAbAAUJFRjEBQBVAQAAAA==.Cynortas:BAAALgAECgIJBgAAAA==.',
Da='Daciana:BAABLgAECn8iAAIFAAkJvRK+FgAsAQAFAAkJvRK+FgAsAQAAAA==.Dados:BAABLgAECn8wAAMUAAkJXh5tDgCBAgAUAAkJXh5tDgCBAgAQAAEJsBRKgAA9AAAAAA==.Daeghun:BAAALgAECgIJBQAAAA==.Dahleigh:BAAALgADCgkJDQAAAA==.Dakanar:BAAALgAECgQJCgAAAA==.Dambrien:BAAALgAECgUJBQAAAA==.Daravus:BAAALgAECgUJCAAAAA==.Darkfox:BAAALgAECgEJAQAAAA==.Darkhazel:BAAALgAECgEJAQAAAA==.Darkkromdor:BAABLgAECn8zAAIOAAkJtR/SFwC0AgAOAAkJtR/SFwC0AgAAAA==.Darloct:BAAALgAECggJEwAAAA==.Dazzlor:BAAALgADCggJCAAAAA==.',
De='Deadelff:BAABLgAECn8kAAMCAAgJ2hZHYwBhAQAVAAYJexvxJwCDAQACAAgJQg9HYwBhAQAAAA==.Deadholypaly:BAAALgADCgEJAwAAAA==.Deadlifts:BAAALgAECgQJCQAAAA==.Deadlighted:BAAALgADCgcJDgABLgAECggJJAACANoWAA==.Deadslinger:BAAALgADCgYJDAAAAA==.Deadtotem:BAAALgADCgkJCQABLgAECggJJAACANoWAA==.Deammon:BAAALgAECgEJAQAAAA==.Deathcat:BAACLgAFFH8UAAIGAAQJLw6JTQDAAAAGAAQJLw6JTQDAAAAuAAQKfzsAAgYACQmjFgc4AB8CAAYACQmjFgc4AB8CAAAA.Deathkiss:BAAALgAECgYJEgAAAA==.Deathpheonix:BAAALgAECgQJBwAAAA==.Deathrat:BAAALgADCgUJBgAAAA==.Deathrixx:BAABLgAFFH8RAAQGAAUJZx4JVABKAQAGAAUJQh4JVABKAQAHAAIJhB3QHACdAAAcAAEJIBhWPABEAAAAAA==.Deathshadowx:BAAALgAECgYJDAAAAA==.Dedbull:BAAALgAECgEJAQAAAA==.Delryth:BAAALgAECgQJBAAAAA==.Demoodius:BAAALgAECgEJAQAAAA==.Denajah:BAAALgAECgIJAgAAAA==.',
Df='Dfault:BAAALgADCgEJAQAAAA==.',
Di='Discharged:BAAALgAECgQJBAABLgAECggJGQALAGIXAA==.',
Dk='Dkdeathblade:BAAALgAECgEJAQAAAA==.Dkpheonix:BAABLgAECn80AAIQAAkJ6xWoGAABAgAQAAkJ6xWoGAABAgAAAA==.',
Do='Dolemite:BAABLgAECn9HAAMXAAcJHhYdLwC/AQAXAAcJHhYdLwC/AQALAAcJcRmOAwCzAQAAAA==.Donalbain:BAACLgAFFH8KAAIBAAMJZw+8UwCqAAABAAMJZw+8UwCqAAAuAAQKfzAAAgEACQkCHlEDAIUCAAEACQkCHlEDAIUCAAAA.Donninban:BAAALgADCgIJAgABLgADCgIJAgANAAAAAA==.Dotdotgoose:BAAALgAECgQJCAAAAA==.',
Dr='Draconz:BAAALgAECgIJAgABLgAECgcJEwANAAAAAA==.Draganpriest:BAABLgAFFH8KAAIJAAMJsxH3HwCQAAAJAAMJsxH3HwCQAAAAAA==.Draganussy:BAAALgADCgEJAQABLgAFFAMJCgAJALMRAA==.Draggo:BAAALgAECgEJAQAAAA==.Drakkira:BAAALgADCgYJBgAAAA==.Draxon:BAAALgAECgEJAQAAAA==.Dremar:BAABLgAECn8gAAMdAAkJ2BAnBAAvAQAdAAgJkQ8nBAAvAQAeAAYJRAyRGQDXAAAAAA==.Druc:BAAALgAECgEJAgAAAA==.',
Du='Durock:BAAALgAECgMJBAAAAA==.',
Dy='Dynaris:BAAALgADCgMJAwAAAA==.',
Ei='Eianna:BAAALgAECgEJAQAAAA==.',
El='Elcachazo:BAAALgAECgIJAgAAAA==.Eldinn:BAAALgADCgcJBgAAAA==.Eleanni:BAAALgAECgQJBAAAAA==.Elenora:BAAALgAECgMJAwAAAA==.Elidor:BAABLgAECn8XAAQIAAgJNwseUADNAAAIAAYJkAweUADNAAADAAQJJxAVFQBvAAAbAAQJbQIwIAA7AAAAAA==.Ellalangley:BAAALgAECgIJAwABLgAFFAMJBQAGAPUQAA==.Elthelas:BAAALgADCgEJAQAAAA==.Eluneatic:BAAALgADCggJCgAAAA==.Elyssaris:BAABLgAECn84AAIcAAkJ4xoyDgAnAgAcAAkJ4xoyDgAnAgAAAA==.Elzulkin:BAAALgADCgcJCgAAAA==.',
Em='Emmdeath:BAABLgAECn8YAAIGAAYJ7QNWDgGaAAAGAAYJ7QNWDgGaAAAAAA==.Emmils:BAABLgAECn8+AAIIAAkJfA1uKgCBAQAIAAkJfA1uKgCBAQAAAA==.Emìly:BAABLgAECn9VAAQLAAkJGiQiAwAyAwALAAkJGiQiAwAyAwAXAAkJCxaKHwAeAgAMAAUJRRUqRgDiAAAAAA==.',
En='Enderelvarg:BAABLgAFFH8FAAIfAAUJbw9TBQARAQAfAAUJbw9TBQARAQAAAA==.Endmicrobuys:BAAALgADCgUJBQAAAA==.Entaria:BAACLgAFFH8GAAIOAAQJmhmFMQBOAQAOAAQJmhmFMQBOAQAuAAQKf0EABA4ACQk7IYMOAPICAA4ACQk7IYMOAPICAA8ABwkxH24NAO4BABIABgm1DGJbAMgAAAAA.',
Eo='Eox:BAAALgADCgMJAwAAAA==.',
Ep='Episkey:BAABLgAECn8gAAMIAAkJMhKOJgCZAQAIAAkJMhKOJgCZAQADAAQJdRcgYQASAQAAAA==.',
Er='Erindaglaze:BAAALgADCgQJBQAAAA==.Erissae:BAAALgADCgEJAgAAAA==.Eropor:BAABLgAECn8iAAMXAAYJexPyQQBlAQAXAAYJexPyQQBlAQALAAMJYQbMigBHAAABLgAFFAQJGAADAEIRAA==.Eroversion:BAACLgAFFH8YAAMDAAQJQhFrMwDgAAADAAQJQhFrMwDgAAAIAAEJtwGnNQAfAAAuAAQKf1YABQMACQlCHq8XAIkCAAMACQlCHq8XAIkCAAgABAkIFj5UANUAAAQAAwm4DUszAJEAABsAAQkAAFWVAAAAAAAA.Eroward:BAAALgAECgcJEwABLgAFFAQJGAADAEIRAA==.',
Es='Esmay:BAABLgAECn8fAAIWAAkJHRRNIADhAQAWAAkJHRRNIADhAQAAAA==.Eso:BAAALgADCgYJCwAAAA==.',
Et='Ethren:BAABLgAECn9RAAIgAAkJ2RgJBABeAgAgAAkJ2RgJBABeAgAAAA==.',
Eu='Eudeyrn:BAAALgAECgYJAwAAAA==.',
Ev='Evilrepu:BAAALgAECgEJAQAAAA==.',
Ey='Eyebrows:BAAALgAECgIJAgAAAA==.',
Ez='Ezikarridge:BAAALgAECgIJAgAAAA==.',
Fa='Faker:BAAALgADCgEJAQAAAA==.Falcone:BAAALgAECgMJBgAAAA==.',
Fe='Felbolter:BAABLgAFFH8GAAIeAAQJaxCsAwAcAQAeAAQJaxCsAwAcAQAAAA==.Feliri:BAAALgAECggJEgAAAA==.',
Fi='Fiddlefaddle:BAAALgAFFAEJAQAAAA==.Filgulfin:BAABLgAECn9bAAMFAAkJBCC8EADLAgAFAAkJBCC8EADLAgATAAgJgRDREwAkAQAAAA==.Finkate:BAABLgAECn8XAAIFAAgJHA4FYwB/AQAFAAgJHA4FYwB/AQAAAA==.Firebad:BAABLgAECn8wAAMeAAkJpxy5AgCFAgAeAAkJpxy5AgCFAgAhAAYJHwrG5ACTAAAAAA==.Firebringer:BAABLgAECn9VAAICAAkJ9A7jSgCmAQACAAkJ9A7jSgCmAQAAAA==.Fistokaestey:BAAALgADCgkJEgABLgAECgkJIwAiANUXAA==.',
Fl='Flaakk:BAAALgADCgcJBwAAAA==.Flamehunter:BAABLgAECn8iAAMCAAkJMRqEHACnAgACAAkJcRmEHACnAgAVAAcJLRdgJACaAQAAAA==.Flo:BAABLgAECn9aAAMQAAkJhxwZCwCeAgAQAAkJhxwZCwCeAgAUAAMJSAcyWAB5AAAAAA==.Floki:BAABLgAECn8UAAIjAAkJqhJnHQBKAQAjAAkJqhJnHQBKAQAAAA==.Flora:BAAALgAECgQJBAAAAA==.Flowing:BAABLgAECn8wAAIkAAkJyxnDAgC9AQAkAAkJyxnDAgC9AQAAAA==.',
Fo='Foods:BAACLgAFFH8dAAMlAAMJiRO/HQC9AAAlAAMJiRO/HQC9AAAjAAIJBgtkGABgAAAuAAQKf4gABCUACQm1HsYBAKICACUACQm1HsYBAKICACMACAlkFa0EAFsBABgAAwnoDE0wAHUAAAAA.Foofsmash:BAAALgADCgUJBgAAAA==.',
Fr='Fripouille:BAAALgADCgMJAwAAAA==.',
Fu='Fustín:BAAALgAECgYJEgAAAA==.Fuzzyewok:BAAALgAECgYJEwAAAA==.',
['Fø']='Føøds:BAAALgADCgMJAwAAAA==.',
Ga='Gaboo:BAAALgAECgkJEwAAAA==.Galangal:BAAALgAECgIJAgAAAA==.Garfman:BAAALgAFFAEJAQAAAA==.Garthrall:BAAALgAECgEJAQAAAA==.',
Gb='Gb:BAACLgAFFH8HAAISAAYJExDZHgAmAQASAAYJExDZHgAmAQAuAAQKfxUAAhIACAnpHYUSAH0CABIACAnpHYUSAH0CAAEuAAUUBAkNABAA8hoA.',
Gh='Ghostinhale:BAABLgAECn8dAAIGAAcJ2RbWEQAqAQAGAAcJ2RbWEQAqAQAAAA==.',
Gi='Gibbshole:BAAALgADCgcJBwAAAA==.Gilorion:BAABLgAECn8XAAIFAAkJ7RbnMgARAgAFAAkJ7RbnMgARAgAAAA==.',
Gl='Glasgoww:BAAALgAECgYJCQABLgAFFAMJCgABAGcPAA==.Gløck:BAAALgAECgIJAgAAAA==.',
Gn='Gnibat:BAAALgAECgQJBwAAAA==.Gnomerlicous:BAAALgADCgkJCQAAAA==.',
Go='Goburina:BAACLgAFFH8VAAMBAAQJohXUHgDbAAABAAQJohXUHgDbAAAWAAEJ2wGuQgAjAAAuAAQKfxgAAgEACQlaC1M9AIwBAAEACQlaC1M9AIwBAAAA.Golias:BAAALgADCgEJAQAAAA==.Gonahrhea:BAAALgAECgEJAQAAAA==.',
Gr='Grenache:BAAALgAECgcJCAABLgAECgcJCAANAAAAAA==.Grievo:BAAALgAECgYJCQAAAA==.Grimdawn:BAAALgAFFAEJAQAAAA==.Grimfist:BAAALgAECgMJAwAAAA==.Grimtankdrud:BAAALgAECgEJAQABLgAECggJGwARAOsPAA==.Grinnir:BAAALgAECgQJBgABLgAECggJGwACAMMYAA==.',
Gu='Guildenstern:BAAALgADCgUJBQABLgAFFAMJCgABAGcPAA==.Gulpron:BAAALgAECgcJCwAAAA==.',
Gy='Gypsiey:BAAALgAECgUJBQAAAA==.',
['Gí']='Gímlí:BAACLgAFFH8LAAIFAAMJABfYNwDLAAAFAAMJABfYNwDLAAAuAAQKfzgAAgUACQm8HiQdAHYCAAUACQm8HiQdAHYCAAAA.',
Ha='Halcyndraag:BAABLgAECn9SAAQkAAkJZxUrIQDQAQAkAAcJaxUrIQDQAQAfAAMJwBcBGgCBAAAZAAEJPQJWRAAeAAAAAA==.Handbannana:BAAALgAECgQJBAAAAA==.Handsome:BAAALgAECgcJDAABLgAECgkJGQAQADQJAA==.Happydk:BAACLgAFFH8RAAMGAAQJniCPPgB6AQAGAAQJniCPPgB6AQAcAAMJKRHrLACVAAAuAAQKfygAAwYACQkdI2MXALoCAAYACQlaIWMXALoCABwABwlKGSMnABsBAAAA.Hartu:BAABLgAECn9NAAIjAAkJfxTyDwDpAQAjAAkJfxTyDwDpAQAAAA==.Harukasan:BAAALgADCgIJAgAAAA==.Hashpipe:BAAALgADCgMJAwAAAA==.Hazl:BAAALgAECgMJBAAAAA==.',
He='Healortank:BAAALgAECgEJAQAAAA==.Healsofpain:BAAALgADCgYJBgAAAA==.Healtardo:BAAALgAFFAIJAgAAAA==.Heiro:BAAALgAFFAEJAQABLgAFFAUJDAAZAEQIAA==.Hellankeller:BAAALgAECgQJBwAAAA==.Hemic:BAACLgAFFH8TAAIKAAMJMB/MEgDtAAAKAAMJMB/MEgDtAAAuAAQKfzQAAwoACQlGI18FAN0CAAoACQlGI18FAN0CACAABAnwGhUQACMBAAAA.Hemmorage:BAAALgAECgYJCgABLgAFFAMJBQAGAPUQAA==.Herbalmist:BAAALgAECgYJDAAAAA==.',
Hi='Higag:BAAALgADCgQJBAAAAA==.Hinaba:BAAALgADCgMJAwAAAA==.Hippypally:BAAALgADCgEJAQAAAA==.Hircine:BAAALgAECgQJBQAAAA==.',
Ho='Holysea:BAAALgAECgYJDAABLgAECgkJOgASAGYTAA==.Horatio:BAAALgAECgEJAQABLgAFFAMJCgABAGcPAA==.',
Hr='Hraken:BAAALgAECgUJBgAAAA==.',
Hu='Hukruun:BAAALgADCgEJAgAAAA==.Huntrinei:BAAALgAECgYJDgAAAA==.',
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
Is='Isam:BAAALgADCgYJBgAAAA==.Isamidor:BAACLgAFFH8QAAIFAAYJlBsAKABnAQAFAAYJlBsAKABnAQAuAAQKfxwAAgUACQmXI+cEAD8DAAUACQmXI+cEAD8DAAAA.Ismokeu:BAACLgAFFH8aAAMUAAQJpBhQCwD5AAAUAAQJbxdQCwD5AAAJAAQJMgryFwDIAAAuAAQKfzoAAhQACQmrGZ4NAIwCABQACQmrGZ4NAIwCAAAA.Ismyn:BAAALgAECgYJBwAAAA==.',
It='Itskemba:BAAALgADCgYJBgAAAA==.',
Iy='Iyania:BAAALgADCgIJAgAAAA==.',
Iz='Izayoi:BAAALgADCgcJCQAAAA==.',
Ja='Jackoneal:BAABLgAECn8lAAIOAAkJYggYpwAtAQAOAAkJYggYpwAtAQAAAA==.Jalidelo:BAABLgAECn9KAAMJAAkJFR6cCADrAgAJAAkJFR6cCADrAgAUAAEJ5gZihgAqAAAAAA==.Jaliwind:BAAALgADCgkJCQAAAA==.Jayan:BAAALgAECgEJAQAAAA==.',
Je='Jenifurr:BAAALgADCgIJAgAAAA==.Jenyx:BAAALgAECgUJCwAAAA==.',
Ji='Jimbowaboki:BAAALgAECgEJAQAAAA==.',
Jo='Johan:BAABLgAECn8eAAIhAAkJMhqFLAAnAgAhAAkJMhqFLAAnAgAAAA==.Jokers:BAABLgAECn8jAAMjAAYJXBUKCADbAAAlAAUJ4g/8WQDoAAAjAAYJShQKCADbAAAAAA==.Jokersfists:BAABLgAECn8XAAICAAYJVg8pGwCxAAACAAYJVg8pGwCxAAAAAA==.Joranbragi:BAABLgAECn8yAAMOAAkJOwxqGQASAQAOAAgJ1QtqGQASAQAPAAMJjAhBEABkAAAAAA==.Jordanjr:BAAALgAECggJEQAAAA==.Jormun:BAAALgADCgEJAQAAAA==.Joshy:BAABLgAECn8dAAIdAAYJsRCBDgBJAQAdAAYJsRCBDgBJAQAAAA==.Jotoonice:BAABLgAECn8aAAIiAAgJjBVjYQC9AQAiAAgJjBVjYQC9AQAAAA==.',
Jt='Jtoothaordan:BAACLgAFFH8YAAQmAAcJexbYCgDpAAAmAAUJzBPYCgDpAAATAAMJsg0uLQBWAAAFAAIJAwgNqwBCAAAuAAQKfy4ABCYACAn9Hw8UAAUCABMACAn9F60gACACACYABgkaJA8UAAUCAAUAAglIIaDPAKsAAAAA.',
Ju='Juglfhednar:BAAALgADCgEJAQAAAA==.Jules:BAAALgAECgUJBQAAAA==.Justbob:BAAALgAECgUJBgAAAA==.',
['Jú']='Júgg:BAAALgAECgQJBgAAAA==.',
Ka='Kaachow:BAABLgAECn8uAAIDAAkJZR+DCQAiAwADAAkJZR+DCQAiAwAAAA==.Kaana:BAABLgAECn9QAAIFAAkJ7xmlHwBpAgAFAAkJ7xmlHwBpAgAAAA==.Kaelenil:BAAALgAECgEJAQAAAA==.Kaestey:BAAALgAECggJDQABLgAECgkJIwAiANUXAA==.Kairis:BAAALgAECgYJCQABLgAFFAUJKAADABYkAA==.Kalia:BAAALgAECgEJAQABLgAECgkJOAAcAOMaAA==.Kallista:BAAALgADCgEJAQAAAA==.Kanoalandiwa:BAAALgAECgEJAQABLgAFFAMJCwAFAAAXAA==.Karthagon:BAABLgAECn8tAAIOAAkJfxxgBACQAgAOAAkJfxxgBACQAgAAAA==.Karungash:BAACLgAFFH8LAAMhAAQJqgoMZAD/AAAhAAQJqgoMZAD/AAAeAAEJVQE+GwA+AAAuAAQKfx0AAyEACAm1Id4QAPMCACEACAm1Id4QAPMCAB4AAgkTEk1SAHcAAAAA.Karva:BAABLgAECn8kAAIRAAkJzBqWBgAqAgARAAkJzBqWBgAqAgAAAA==.Karvy:BAABLgAECn8kAAIbAAgJXB4IBACdAQAbAAgJXB4IBACdAQABLgAECgkJJAARAMwaAA==.Kash:BAAALgADCgUJBQABLgAFFAUJEwAEACYlAA==.Kayzer:BAAALgADCgYJGAAAAA==.',
Ke='Kelonaar:BAACLgAFFH8bAAIWAAYJ9x/tDABwAQAWAAYJ9x/tDABwAQAuAAQKfygAAxYACQksIqEWADECABYACQksIqEWADECABoAAgn1Gg45AEoAAAAA.Kelya:BAAALgAECgUJBQABLgAFFAYJGwAWAPcfAA==.Kerrie:BAAALgADCgEJAQAAAA==.',
Kh='Kharys:BAAALgAECgUJDAAAAA==.Khthonious:BAABLgAECn8VAAICAAcJBx4TOwDbAQACAAcJBx4TOwDbAQAAAA==.',
Ki='Kibblsncrits:BAAALgAECgIJAwABLgAECgkJEgANAAAAAA==.Kickingdonut:BAACLgAFFH8FAAILAAMJNx8sHADtAAALAAMJNx8sHADtAAAuAAQKfywAAwsACAk7IxkJAOcCAAsACAk7IxkJAOcCAAwABgn1GUI3AG4BAAAA.Killerhottie:BAAALgAECgEJAQAAAA==.Killermoomoo:BAAALgAECgUJCwAAAA==.Kinoh:BAAALgADCgkJEAAAAA==.Kittykarma:BAAALgAECgUJBQAAAA==.',
Kl='Kloverr:BAAALgAECgIJAgAAAA==.Klub:BAAALgADCgYJBgAAAA==.',
Ko='Kollita:BAAALgAECgEJAQAAAA==.Komatsu:BAAALgAECgEJAQAAAA==.Kombatkarl:BAAALgAECgEJAQAAAA==.Koramere:BAAALgADCgcJBwAAAA==.',
Kr='Kretaios:BAAALgADCgQJBAAAAA==.Kromir:BAAALgAECgQJBwAAAA==.Kromnar:BAAALgADCgEJAQAAAA==.Kronixrage:BAAALgAECgYJCwAAAA==.Kronn:BAAALgAECgYJBwAAAA==.Krooler:BAAALgAECgQJCAAAAA==.Krum:BAACLgAFFH8gAAIOAAUJaR8DKQBnAQAOAAUJaR8DKQBnAQAuAAQKfx4AAg4ACAmsHYRRANQBAA4ACAmsHYRRANQBAAAA.',
Ku='Kungfoumoo:BAAALgAECgEJAQAAAA==.',
La='Ladgarkk:BAAALgADCggJFQAAAA==.Lanval:BAABLgAECn9eAAIOAAkJgBtIIgB9AgAOAAkJgBtIIgB9AgAAAA==.Lardend:BAABLgAECn8bAAIVAAgJsAkQCwDsAAAVAAgJsAkQCwDsAAAAAA==.Latinlover:BAAALgADCgEJAQAAAA==.Laurian:BAAALgADCgcJDwAAAA==.Laurì:BAAALgAECgMJBQABLgAECgkJVQALABokAA==.',
Le='Leaky:BAAALgAECgIJBAAAAA==.Leetah:BAACLgAFFH8dAAIbAAMJ0R/MCAAIAQAbAAMJ0R/MCAAIAQAuAAQKf5EAAxsACQlhI5AAACsDABsACQlhI5AAACsDAAQABQkuIGIDAHIBAAAA.Leftblank:BAABLgAECn8UAAMGAAgJOAlRFwD4AAAGAAgJOAlRFwD4AAAHAAQJPAPcLgBkAAAAAA==.Legitimas:BAAALgAECgEJAQAAAA==.Lemix:BAAALgAECgMJDAAAAA==.Letmetameyou:BAAALgAECgYJBgAAAA==.',
Li='Liasong:BAAALgADCgMJAwAAAA==.Lilyandra:BAAALgADCgkJEAAAAA==.Lilyara:BAAALgADCgIJAgAAAA==.Lilyoptra:BAABLgAECn8VAAIhAAcJKwO2MABGAAAhAAcJKwO2MABGAAABLgAECgkJFwAIADcLAA==.Lindrael:BAAALgADCgEJAQAAAA==.Liszt:BAAALgAECgYJBgAAAA==.Litallya:BAAALgAECggJDQAAAA==.Littletush:BAABLgAECn8dAAIFAAkJNAwgDwCAAQAFAAkJNAwgDwCAAQAAAA==.Livingdemon:BAAALgAECgUJDwAAAA==.',
Lm='Lminus:BAAALgAECgYJEgAAAA==.',
Lo='Lockolus:BAAALgAECgMJAwAAAA==.Lockpockets:BAAALgADCgEJAQAAAA==.Longshot:BAAALgAECgIJAgABLgAECgUJCwANAAAAAA==.Lootie:BAAALgAECggJDgAAAA==.Loriane:BAAALgAECgUJCAABLgAECgkJKAADAAIgAA==.Lorianth:BAAALgADCgcJDgAAAA==.Lotharbacco:BAAALgAECgMJAwAAAA==.Lovegood:BAAALgADCgEJAQAAAA==.Loveisbeauty:BAAALgAECgUJBwAAAA==.Lowki:BAAALgAECgEJAgAAAA==.',
Lu='Lundigras:BAAALgADCgkJCQAAAA==.',
Ly='Lychi:BAAALgAECgYJDAAAAA==.Lylora:BAACLgAFFH8oAAIDAAUJFiTBBgACAgADAAUJFiTBBgACAgAuAAQKf08AAgMACQm8JOIBALoDAAMACQm8JOIBALoDAAAA.Lysera:BAAALgADCgMJAwAAAA==.',
['Lê']='Lêmonaide:BAABLgAECn8tAAMUAAkJTQ+oJgCQAQAUAAkJTQ+oJgCQAQAQAAUJAgXEagBzAAAAAA==.',
Ma='Madesh:BAABLgAECn9LAAMRAAkJYxv+BQA8AgARAAkJtxj+BQA8AgACAAkJZBozKAAqAgAAAA==.Madman:BAABLgAECn8vAAIXAAkJTA9jOQCMAQAXAAkJTA9jOQCMAQAAAA==.Maelle:BAABLgAECn9SAAIOAAkJ2iJZDAACAwAOAAkJ2iJZDAACAwAAAA==.Magekaestey:BAABLgAECn8jAAIiAAkJ1RfHPAAnAgAiAAkJ1RfHPAAnAgAAAA==.Majandra:BAAALgAECgUJDAAAAA==.Malala:BAAALgAECgcJDQABLgAFFAIJFQAUAD4dAA==.Malyndra:BAABLgAECn8zAAMVAAkJNB0EDwA1AgAVAAkJixsEDwA1AgARAAYJ9hksDgBvAQAAAA==.Malyssa:BAAALgADCgIJAgAAAA==.Marianne:BAAALgADCgYJBwAAAA==.Marle:BAAALgAECgEJBAAAAA==.Marvolt:BAABLgAECn8YAAIhAAgJcA0RbQBiAQAhAAgJcA0RbQBiAQAAAA==.Masy:BAAALgAECgEJAQAAAA==.',
Mc='Mcrae:BAAALgAECgYJBwAAAA==.',
Md='Md:BAAALgAECgEJAgAAAA==.',
Me='Medrare:BAAALgAECgEJAQAAAA==.Meekastraza:BAAALgAECgIJAgAAAA==.Melon:BAAALgADCgEJAQABLgAECgkJDQANAAAAAA==.Meriam:BAAALgAECgEJAgABLgAFFAMJBQAGAPUQAA==.Merlot:BAAALgAECgcJCAAAAA==.Mesmash:BAABLgAECn8wAAIjAAkJniFHBADjAgAjAAkJniFHBADjAgAAAA==.Metadk:BAAALgAECgQJCAABLgAECggJGQALAGIXAA==.Metahunt:BAAALgAECgIJAgABLgAECggJGQALAGIXAA==.Metamasters:BAAALgAECgQJBgABLgAECggJGQALAGIXAA==.Metatotem:BAAALgAECgIJBAABLgAECggJGQALAGIXAA==.Metavoker:BAAALgAECgUJBQABLgAECggJGQALAGIXAA==.',
Mi='Mialtaa:BAABLgAECn8vAAIMAAkJDxvjCwB2AgAMAAkJDxvjCwB2AgAAAA==.Midgiit:BAAALgAECgUJBQABLgAFFAMJBQAGAPUQAA==.Miink:BAAALgADCgYJBgAAAA==.Milkurs:BAAALgAECgQJBwAAAA==.Miniborg:BAABLgAECn8iAAIFAAkJ+xo5HAB7AgAFAAkJ+xo5HAB7AgABLgAFFAcJGwAOAK0dAA==.Minidude:BAAALgAECgYJEAAAAA==.Minionghost:BAAALgADCggJCAAAAA==.Miyuki:BAAALgAECgQJBgAAAA==.Mizzen:BAAALgAFFAEJAQABLgAFFAcJIQAQAKMVAA==.',
Mj='Mjolnir:BAAALgAECgcJBgAAAA==.',
Mo='Moejojojo:BAABLgAECn8WAAILAAkJ0yF4DwBTAgALAAkJ0yF4DwBTAgAAAA==.Monkter:BAABLgAECn8ZAAQLAAgJYheyHADJAQALAAgJYheyHADJAQAXAAEJ/gbfbgAmAAAMAAEJfggUoAAiAAAAAA==.Monsignore:BAAALgADCgQJBAAAAA==.Moofasaha:BAAALgAECgkJEAAAAA==.Mooheals:BAAALgADCgEJAQAAAA==.Moonk:BAAALgAECgcJBQAAAA==.Morangia:BAAALgADCgcJBwAAAA==.Morbus:BAAALgAECgUJBQAAAA==.Morduos:BAAALgAECgcJBgABLgAECggJFQACAAceAA==.Morog:BAACLgAFFH8WAAMmAAYJURpxBQC4AQAmAAYJURpxBQC4AQAFAAEJ0w1tqwBCAAAuAAQKfykABBMACQmpGyMsAM0BABMABgmOHSMsAM0BAAUABgkbGq0/ALABACYABgnqE/UpAFEBAAAA.Morragan:BAAALgAECgQJBQAAAA==.Mortegom:BAAALgADCgcJBwAAAA==.Moráthi:BAAALgADCgcJBwAAAA==.',
Mu='Mulvan:BAAALgAECggJEQAAAA==.',
My='Myinja:BAAALgAECgQJCAABLgAECggJGQALAGIXAA==.Myrddinwyllt:BAAALgAECgYJDAAAAA==.Myzac:BAAALgAECgEJAQAAAA==.',
Mz='Mzharipants:BAAALgADCgIJAgAAAA==.',
Na='Naadra:BAAALgAECgEJAQAAAA==.Nabû:BAAALgADCggJDwAAAA==.Naema:BAAALgAECggJDgAAAA==.Nalid:BAACLgAFFH8TAAIEAAUJJiW2AgCqAQAEAAUJJiW2AgCqAQAuAAQKf0QAAwQACQnAJkAAAIwDAAQACQnAJkAAAIwDAAgAAQmuAl6mABsAAAAA.Nanarus:BAACLgAFFH8VAAIUAAIJPh2XEgCPAAAUAAIJPh2XEgCPAAAuAAQKf10AAxQACQnTINMAAC0DABQACQnTINMAAC0DABAABgnkA+VWALgAAAAA.Nanosec:BAAALgAECgEJAQAAAA==.Nansea:BAAALgAECgEJAgAAAA==.Nashalie:BAABLgAECn80AAIhAAkJsR5MAwBrAgAhAAkJsR5MAwBrAgAAAA==.Natedawg:BAAALgAECgUJCQAAAA==.',
Ne='Neezzdutzz:BAAALgAECgQJBAAAAA==.Nefele:BAABLgAECn8hAAIBAAkJ5RUWIwA8AgABAAkJ5RUWIwA8AgAAAA==.Nepheli:BAACLgAFFH8GAAICAAMJUxefVgDrAAACAAMJUxefVgDrAAAuAAQKf00AAgIACQlrJF4DAFIDAAIACQlrJF4DAFIDAAAA.Newrhu:BAAALgAECgYJBwAAAA==.Nexbasia:BAACLgAFFH8YAAIEAAMJ1RIGBwDBAAAEAAMJ1RIGBwDBAAAuAAQKf3wAAwQACQmYH7QAAMQCAAQACQmYH7QAAMQCAAMAAgn2Apr6ABoAAAAA.',
Ni='Nickyboy:BAABLgAECn8qAAQeAAcJmyLhBQAKAgAeAAcJmyLhBQAKAgAhAAIJvg54BwFhAAAdAAEJrBd0PQA3AAAAAA==.Nightevel:BAAALgAECgUJBQAAAA==.Nihimetal:BAAALgAECgYJCQAAAA==.Nikash:BAABLgAECn80AAMIAAkJFBNVHADnAQAIAAkJFBNVHADnAQADAAYJ+QhgfwC8AAAAAA==.Nisato:BAAALgAECgUJBQAAAA==.',
No='Noctum:BAAALgAECgYJEAAAAA==.Nommei:BAAALgAECgcJEwAAAA==.Northic:BAAALgAECgYJBgABLgAECgkJNQAGAPEgAA==.Nortikolait:BAAALgAECgEJAQABLgAECgkJNQAGAPEgAA==.',
Ny='Nyriah:BAAALgAECgUJCwAAAA==.Nyxys:BAAALgAECgMJAwAAAA==.',
Ob='Obm:BAAALgAECgUJCwAAAA==.',
Oc='Octoface:BAAALgAECgYJBQAAAA==.Octt:BAACLgAFFH8HAAIhAAMJoRntagDuAAAhAAMJoRntagDuAAAuAAQKfyAAAiEACQk5HEEIAI8BACEACQk5HEEIAI8BAAAA.',
Of='Offal:BAABLgAECn82AAQjAAYJjxUhBgAaAQAYAAYJCAsJGAA5AQAjAAYJjxUhBgAaAQAlAAEJJQV2swAjAAAAAA==.',
Ol='Olanna:BAAALgAECgYJDAAAAA==.Oldcannabis:BAAALgAECgQJCwAAAA==.',
Om='Ominis:BAAALgAECgYJCgAAAA==.',
Oo='Oomaw:BAAALgAFFAEJAQAAAA==.',
Or='Orcal:BAACLgAFFH8hAAIkAAYJshT7KQAgAQAkAAYJshT7KQAgAQAuAAQKfx0AAiQACAn7GnQQAHECACQACAn7GnQQAHECAAAA.Ormie:BAAALgAECgQJBAAAAA==.Orney:BAAALgADCgcJBwAAAA==.Ornimus:BAABLgAECn8jAAQPAAgJDBE4BwAEAQAPAAgJDBE4BwAEAQAOAAQJEARkKAGJAAASAAIJLgWgGwBGAAAAAA==.Ortian:BAAALgAECgEJAQABLgAECgUJCAANAAAAAA==.',
Ot='Otherrhu:BAAALgAECgYJCAAAAA==.',
Oz='Ozo:BAABLgAECn8dAAIFAAcJqBIgbQBnAQAFAAcJqBIgbQBnAQAAAA==.',
Pa='Paiva:BAAALgAECgYJCQAAAA==.Palandor:BAAALgADCgMJAwAAAA==.Pallyscorned:BAABLgAECn9FAAIPAAkJ/iHjAgD3AgAPAAkJ/iHjAgD3AgAAAA==.Pampas:BAABLgAECn8bAAMBAAkJkgSndAD/AAABAAkJkgSndAD/AAAWAAEJ5AFvwwAZAAAAAA==.Pandamonic:BAAALgAECgQJBAAAAA==.Panduh:BAAALgAECgYJCQABLgAFFAQJEQAGAJ4gAA==.Paxdei:BAAALgAECgUJCQAAAA==.',
Pe='Ped:BAAALgAECgQJBgAAAA==.',
Ph='Phenixy:BAAALgAECgYJDAAAAA==.Phoebell:BAAALgAECgYJDQAAAA==.',
Pi='Pinkducky:BAABLgAECn8nAAIGAAcJ1gdSHgDJAAAGAAcJ1gdSHgDJAAAAAA==.',
Pl='Platinumsoul:BAAALgADCgIJAgAAAA==.Plen:BAACLgAFFH8FAAIGAAMJ9RC+pwDMAAAGAAMJ9RC+pwDMAAAuAAQKfzAAAxwACQnNH+sDAMMBAAYACQmnHFo1AGECABwABgk/IOsDAMMBAAAA.',
Po='Ponder:BAAALgAECgYJCgAAAA==.Poppyseed:BAAALgAECgQJBAAAAA==.Poquads:BAAALgAECgQJCgAAAA==.',
Pr='Priestdoof:BAAALgADCgcJBwAAAA==.Primaris:BAAALgAECgcJDAAAAA==.Prinnce:BAAALgAECgcJDgABLgAECgkJVQALABokAA==.Príestatute:BAAALgAECgUJBQABLgAFFAMJCwAFAAAXAA==.',
Pu='Pulmifinger:BAAALgAECgEJAwAAAA==.Punka:BAAALgAECgEJAQAAAA==.Purplesea:BAAALgADCgcJDQABLgAECgkJOgASAGYTAA==.',
Pv='Pve:BAAALgAECgcJCAAAAA==.',
Py='Pygon:BAAALgAECgIJAgAAAA==.',
Qi='Qilt:BAAALgADCgcJBwAAAA==.',
Qu='Quasar:BAABLgAECn8lAAIiAAkJmBgVQQAZAgAiAAkJmBgVQQAZAgAAAA==.',
Ra='Raaluur:BAAALgAECgQJBwAAAA==.Radra:BAACLgAFFH8JAAMVAAQJVwUFEwCYAAAVAAQJ7gMFEwCYAAACAAMJ0ARYPwBzAAAuAAQKf1AABBUACQm7FccDANsBABUACQlAFccDANsBABEABwnEDZYDACQBAAIABgn6DN8ZALkAAAAA.Radras:BAAALgAECgcJCQAAAA==.Raeku:BAABLgAECn8tAAImAAkJkCAUBgDCAgAmAAkJkCAUBgDCAgAAAA==.Rainee:BAAALgADCgYJBwAAAA==.Raja:BAAALgAECgUJDwAAAA==.Rathalo:BAAALgAECgQJBgAAAA==.Rav:BAAALgADCgUJBQAAAA==.Ravick:BAAALgADCgEJAQAAAA==.Razensetral:BAAALgAECggJCAAAAA==.Razzlor:BAAALgADCgUJBQAAAA==.',
Re='Reducto:BAABLgAECn8hAAMRAAYJhRXmFwDiAAACAAYJnBNxfgAjAQARAAUJPxXmFwDiAAAAAA==.Reenailinefh:BAAALgADCgcJDgAAAA==.Relitha:BAAALgADCgUJCQAAAA==.Remeii:BAABLgAECn8iAAMBAAgJJghPgADgAAABAAcJtgRPgADgAAAWAAYJUQP9cQCVAAAAAA==.Retribution:BAABLgAECn85AAIOAAkJ5hM9SADtAQAOAAkJ5hM9SADtAQAAAA==.Reylexgt:BAAALgAECgEJAQAAAA==.',
Rh='Rhaenera:BAAALgAECgMJCgABLgAECgkJVQALABokAA==.Rhage:BAAALgADCgkJCQAAAA==.',
Ri='Richcraniums:BAAALgADCgcJBwAAAA==.Rivkah:BAAALgAECgEJAQAAAA==.',
Ro='Roachers:BAAALgADCgIJAgAAAA==.Robomurph:BAAALgADCggJDwAAAA==.Rolas:BAAALgAECgYJAgAAAA==.Ronfax:BAACLgAFFH8+AAMBAAgJQCO4AAAyAwABAAgJQCO4AAAyAwAWAAQJthXyFQDrAAAuAAQKfywAAwEACQm2IzwFAF8DAAEACQm2IzwFAF8DABYABgmeHN8qAJwBAAAA.Ronia:BAAALgADCgIJAgABLgAECggJGwACAMMYAA==.Rooss:BAAALgAECgcJEgAAAA==.Roqane:BAAALgAECgQJBAAAAA==.Roserade:BAABLgAECn8UAAMcAAkJQxSKHwBYAQAcAAkJ5xOKHwBYAQAHAAEJ+AyqPAAtAAAAAA==.Rothkin:BAAALgADCgMJAwAAAA==.Rotreiter:BAAALgADCgEJAQAAAA==.Rowdyredneck:BAAALgADCgMJAwABLgAECggJGQALAGIXAA==.',
Ru='Rukea:BAAALgAECgQJBAAAAA==.Rul:BAAALgAFFAEJAQABLgAFFAQJEQAGAJ4gAA==.',
Ry='Ryllae:BAAALgAECgQJBQABLgAECgkJHgAVAFciAA==.Ryuusythe:BAAALgADCgcJBwAAAA==.Ryân:BAAALgADCgEJAQAAAA==.',
['Rì']='Rììdìì:BAACLgAFFH8GAAIdAAMJtgdRBwCzAAAdAAMJtgdRBwCzAAAuAAQKfxQAAh0ABwnxFJYCAIkBAB0ABwnxFJYCAIkBAAEuAAUUAwkLAAUAABcA.',
Sa='Saara:BAAALgADCgEJAQAAAA==.Sackhammer:BAAALgAECgQJBAAAAA==.Saint:BAAALgAECgkJDwAAAA==.Salopard:BAAALgAECgIJAgAAAA==.Samson:BAABLgAECn8ZAAQLAAgJ8xvRIgCaAQALAAcJ6xvRIgCaAQAMAAUJtxHfTgDFAAAXAAIJ3wpgqgBJAAABLgAECgUJCwANAAAAAA==.Sanivan:BAABLgAECn8VAAIVAAcJ+hdxGgDvAQAVAAcJ+hdxGgDvAQAAAA==.Sanoan:BAAALgAECgQJBQAAAA==.Saori:BAAALgAECgEJAQAAAA==.Sappy:BAABLgAECn8aAAQgAAcJdR9BCQCuAQAgAAYJsh5BCQCuAQAKAAQJrxwzOwA/AQAnAAQJ8BLcCQDFAAABLgAFFAQJEQAGAJ4gAA==.Sarinae:BAABLgAECn8qAAQkAAkJeAdaDQCgAAAkAAgJzwVaDQCgAAAfAAEJGQ4nCgAsAAAZAAEJwAEQRAAfAAAAAA==.Sarmuc:BAABLgAECn8dAAMaAAkJtxZcAwB/AQAaAAkJtxZcAwB/AQAWAAEJXwuesAAoAAAAAA==.Sarnluz:BAAALgAECgEJAQABLgAECggJEQANAAAAAA==.Saryda:BAAALgAECgYJDgABLgAECgcJCAANAAAAAA==.Sauda:BAAALgAECgMJBAAAAA==.Saurian:BAAALgADCgEJAQAAAA==.',
Sc='Schadoww:BAAALgAECggJDQABLgAFFAMJBQAGAPUQAA==.Scubagal:BAAALgAECgYJDQAAAA==.Scy:BAAALgAECggJDgAAAA==.Scythraza:BAABLgAECn8/AAMkAAgJTBtqAgDdAQAkAAgJTBtqAgDdAQAZAAIJTw7LDABHAAAAAA==.',
Se='Seablue:BAAALgAECgMJBQABLgAECgkJOgASAGYTAA==.Sedaleice:BAAALgAECgEJAQAAAA==.Sedge:BAAALgADCgEJAQAAAA==.Seedsprayer:BAAALgAECgYJDAAAAA==.Selara:BAAALgAECgMJAwAAAA==.Sellenah:BAABLgAECn8bAAICAAgJwxjOXAByAQACAAgJwxjOXAByAQAAAA==.Sensu:BAABLgAECn8UAAMJAAcJIA06EwCuAAAJAAcJIA06EwCuAAAQAAEJHwOXmAAgAAAAAA==.Sensual:BAAALgAECgYJAwAAAA==.Sernian:BAABLgAFFH8IAAIFAAQJWBTDJQAPAQAFAAQJWBTDJQAPAQABLgAFFAUJHwAOAPgjAA==.Seä:BAABLgAECn86AAISAAkJZhMXHAAjAgASAAkJZhMXHAAjAgAAAA==.',
Sh='Shadoweave:BAABLgAECn8dAAIQAAkJqwfcMwBJAQAQAAkJqwfcMwBJAQAAAA==.Shampooshady:BAAALgAECgMJBAAAAA==.Shamtea:BAACLgAFFH8NAAIWAAMJEwz5HwCkAAAWAAMJEwz5HwCkAAAuAAQKfzYAAhYACQkmFPEGAHsBABYACQkmFPEGAHsBAAAA.Shandrin:BAAALgAECgIJAgAAAA==.Shapadin:BAAALgADCgcJBwABLgAECgkJGgAIAH0WAA==.Shapzan:BAABLgAECn8aAAMIAAgJfRYhLwBjAQAIAAgJfRYhLwBjAQAbAAUJ3g2KDgCcAAAAAA==.Shareliss:BAAALgADCgYJBgAAAA==.Sharks:BAAALgAECgQJDwAAAA==.Shiik:BAAALgAECgYJBwABLgAECgcJGQASABIYAA==.Shivant:BAACLgAFFH8HAAIBAAMJYA8XKwCeAAABAAMJYA8XKwCeAAAuAAQKfzoAAwEACQlJHa0VAJ0CAAEACQlJHa0VAJ0CABYAAglDBZ6bAEEAAAAA.Shmeegleroop:BAAALgAECgYJDgAAAA==.Shroomhunter:BAAALgAECgEJAQAAAA==.Shîvå:BAACLgAFFH8IAAIRAAMJ6SGLAwACAQARAAMJ6SGLAwACAQAuAAQKfzEAAhEACQniID0CAOQCABEACQniID0CAOQCAAAA.',
Si='Sideburns:BAAALgAECgMJAwAAAA==.Silvertime:BAAALgADCgYJBwAAAA==.Sindice:BAAALgAECgYJCwABLgAFFAgJPgABAEAjAA==.',
Sk='Skaa:BAAALgAECgEJAwAAAA==.',
Sl='Slammy:BAAALgAECgQJBAAAAA==.Slanesh:BAAALgAECgIJAgAAAA==.Slimpooshady:BAACLgAFFH8MAAIbAAMJvQw9FgB3AAAbAAMJvQw9FgB3AAAuAAQKfzQAAwMACQkWEn0oAA4CAAMACQkWEn0oAA4CABsACQmmEzcRANgBAAAA.Sloth:BAABLgAECn87AAIcAAkJICFOAQDGAgAcAAkJICFOAQDGAgAAAA==.',
So='Solaspirus:BAABLgAECn8uAAMCAAkJ6BsEJAA/AgACAAkJ6BsEJAA/AgARAAEJawxCNwAqAAAAAA==.Solinius:BAAALgAECgQJBQAAAA==.Sope:BAAALgAECgYJDQABLgAECggJDgANAAAAAA==.Sorhtx:BAAALgAECgUJBwAAAA==.Sostoned:BAAALgAECgEJAQABLgAECgkJNAAgAPEcAA==.Soulomatic:BAAALgADCgcJBwAAAA==.',
Sp='Spectors:BAACLgAFFH8HAAIdAAMJjQWLBwCvAAAdAAMJjQWLBwCvAAAuAAQKf0gAAx0ACAmMEuUDAD0BAB0ABwkcFeUDAD0BACEABwnnA3DBAMoAAAAA.Spekturx:BAAALgAECgEJAQAAAA==.Spideygirl:BAABLgAECn8WAAISAAgJPxzPEQCFAgASAAgJPxzPEQCFAgAAAA==.Sprayinnseed:BAAALgAECgMJBAAAAA==.Sprayinseed:BAAALgADCgMJAwAAAA==.',
Sq='Squarepants:BAAALgAECgQJCQABLgAECgQJDwANAAAAAA==.',
St='Stabon:BAABLgAECn8lAAIKAAkJcwlDHwCcAQAKAAkJcwlDHwCcAQAAAA==.Stalaediir:BAAALgADCgQJBAAAAA==.Stardre:BAAALgADCgQJBQAAAA==.Stevesmith:BAAALgAECgEJAgAAAA==.Stonedrage:BAAALgADCgEJAQAAAA==.Stormspirits:BAAALgADCgUJBQAAAA==.Sturdyy:BAAALgADCgMJAwAAAA==.Stãrkïllér:BAAALgADCgMJAwAAAA==.',
Su='Sugarmarks:BAAALgAECgYJDwAAAA==.',
Sw='Sweetstorm:BAABLgAECn94AAIVAAkJFg8BBgByAQAVAAkJFg8BBgByAQAAAA==.',
Sy='Synvara:BAAALgADCgUJBQAAAA==.',
['Sê']='Sêphiroth:BAABLgAECn83AAISAAkJWxeEFABqAgASAAkJWxeEFABqAgAAAA==.',
Ta='Taekoad:BAAALgADCgIJAgAAAA==.Tahlia:BAAALgAECgEJAQAAAA==.Tania:BAABLgAECn8aAAIOAAgJsxMTXwCzAQAOAAgJsxMTXwCzAQAAAA==.Taredelaria:BAAALgAECgEJBAAAAA==.Tarixx:BAABLgAFFH8GAAMOAAMJ/w5hJACjAAAOAAIJQg5hJACjAAAPAAEJeRA0GgAqAAAAAA==.Tazanoth:BAACLgAFFH8IAAQFAAMJBBLAcQC8AAAFAAMJ0Q/AcQC8AAAmAAIJKQ7lKwCDAAATAAEJTArEJgBPAAAuAAQKfyEAAyYACQmaG4kPADYCACYACQmQGokPADYCABMABglBGtYwALABAAAA.',
Te='Teasa:BAACLgAFFH8PAAIFAAMJHw3zNQDRAAAFAAMJHw3zNQDRAAAuAAQKf0IAAgUACQnZGYohAF8CAAUACQnZGYohAF8CAAAA.Tekeela:BAAALgAECgYJCgABLgAFFAcJFAAFAN8VAA==.Tekeelà:BAACLgAFFH8UAAQFAAcJ3xVDAgB7AQAFAAcJ3xVDAgB7AQATAAEJVgAiLgA1AAAmAAIJXwEmIAAYAAAuAAQKfzMABAUACQmJIaMVAIoCAAUACQkHH6MVAIoCACYACQn8Gp8PADUCABMABwm3EeY5AHoBAAAA.Tekkamaki:BAAALgADCgcJCAAAAA==.',
Th='Thalion:BAABLgAECn8gAAMFAAYJ0ASZNAB7AAAFAAYJ0ASZNAB7AAAmAAUJcgF+VQBXAAAAAA==.Theenna:BAABLgAECn8XAAMhAAgJ3AkBFwC+AAAhAAcJYgcBFwC+AAAeAAQJuQumCQCeAAAAAA==.Thetodd:BAAALgAECgIJAgAAAA==.Thianna:BAABLgAECn8pAAMSAAkJyBn5GwAkAgASAAkJyBn5GwAkAgAOAAgJdRJzHwDmAAAAAA==.Thiculuskage:BAABLgAECn8YAAISAAkJvB77BwAMAwASAAkJvB77BwAMAwAAAA==.Thinkso:BAAALgADCgcJGwAAAA==.Thobu:BAAALgAECgcJCwAAAA==.Thodos:BAAALgADCgEJAQAAAA==.Thornscale:BAABLgAECn9OAAQkAAkJ3ho3EQBcAgAkAAkJ3ho3EQBcAgAZAAYJogvrKAAsAQAfAAYJbhZXAgAnAQAAAA==.Thorrent:BAAALgADCgcJDQAAAA==.',
Ti='Tigolcrittys:BAAALgAECgcJEgABLgAFFAMJCwAFAAAXAA==.Timeforloads:BAABLgAECn8rAAMDAAkJFx+uMgDUAQADAAYJxB+uMgDUAQAIAAcJOhUdNABIAQAAAA==.Tirria:BAAALgAECgYJCQAAAA==.',
To='Tolk:BAAALgAECgcJEQAAAA==.Tomzombe:BAAALgAECgQJBgAAAA==.Totem:BAABLgAECn8WAAIWAAgJvQu3RQAdAQAWAAgJvQu3RQAdAQAAAA==.Totenz:BAAALgADCgYJBgAAAA==.Tovê:BAAALgAECgkJCQAAAA==.',
Tr='Traveler:BAAALgAECgIJAgAAAA==.Trickyflamom:BAABLgAECn8aAAIiAAcJzBwDCwCzAQAiAAcJzBwDCwCzAQABLgAFFAQJIgAiAPYaAA==.Troloq:BAABLgAECn85AAQdAAkJfx2BCADgAQAhAAgJHhuKNwD7AQAdAAgJWReBCADgAQAeAAYJTRoEFAAQAQAAAA==.Trondoom:BAAALgADCgYJBgAAAA==.',
Tu='Tugboattimmy:BAAALgAECgEJAQAAAA==.Tulisha:BAAALgAECgUJCgAAAA==.Turero:BAABLgAECn8WAAISAAcJkAfYCwD2AAASAAcJkAfYCwD2AAABLgAFFAQJGAADAEIRAA==.Turger:BAAALgAECgUJCAABLgAECgkJEAANAAAAAA==.Turinnii:BAAALgADCgcJBwAAAA==.',
Ul='Uller:BAABLgAECn8oAAIiAAkJDhrQMABWAgAiAAkJDhrQMABWAgAAAA==.',
Um='Umbrafang:BAAALgAECgEJBAAAAA==.',
Un='Unholyspirit:BAAALgAECgQJDwAAAA==.',
Va='Vahlorraa:BAABLgAECn8oAAMSAAgJGw8eCABPAQASAAcJMhAeCABPAQAOAAEJdAODeQATAAAAAA==.Vaimei:BAACLgAFFH8GAAIhAAMJQBUANgCxAAAhAAMJQBUANgCxAAAuAAQKfz0AAx4ACQlBIy8CAKICAB4ACAk9Iy8CAKICACEACAlhID8WAJ8CAAAA.Valashune:BAAALgADCgEJAQAAAA==.Valsilla:BAAALgAECgYJBgABLgAECgkJHgAVAFciAA==.Vapor:BAABLgAECn80AAIgAAkJ8RygAABaAgAgAAkJ8RygAABaAgAAAA==.Varaine:BAAALgAECgMJAwAAAA==.Varanius:BAAALgAECgEJAgAAAA==.',
Ve='Veebes:BAAALgAECggJCAAAAA==.Veebs:BAABLgAECn8tAAQlAAkJFRsVAwAfAgAlAAgJSBoVAwAfAgAYAAIJuB4OCwC2AAAjAAEJAAAySAAuAAAAAA==.Velóran:BAAALgADCgcJBwAAAA==.Vendola:BAABLgAECn8gAAIiAAgJaQboqgAqAQAiAAgJaQboqgAqAQAAAA==.Vento:BAABLgAECn8VAAIGAAgJjxWuYgCjAQAGAAgJjxWuYgCjAQAAAA==.Verité:BAABLgAECn8UAAMfAAgJ8gwzDwAXAQAfAAcJdg4zDwAXAQAkAAcJfQmBTgD0AAAAAA==.Veterpeinss:BAAALgADCggJDgAAAA==.',
Vi='Viento:BAAALgADCgcJBwAAAA==.Villiveil:BAAALgAECgEJAQABLgAFFAQJBgAOAJoZAA==.Vintersorg:BAAALgAECgUJCQAAAA==.Virauca:BAABLgAECn9OAAICAAkJjhYtLgAOAgACAAkJjhYtLgAOAgAAAA==.Viuhl:BAAALgADCgQJAwAAAA==.',
Vo='Vodgrax:BAAALgAECgIJAgAAAA==.Voidstar:BAAALgAECgUJDAAAAA==.Voltimand:BAAALgAECgEJAQABLgAFFAMJCgABAGcPAA==.',
Vv='Vvicked:BAABLgAECn8gAAIGAAgJrCI8FwC7AgAGAAgJrCI8FwC7AgAAAA==.',
Vy='Vynesta:BAABLgAECn8eAAIVAAkJVyKvAwAZAwAVAAkJVyKvAwAZAwAAAA==.',
Wa='Wala:BAAALgAECgcJDAAAAA==.Wamoo:BAAALgAECgEJAgAAAA==.Wanagi:BAAALgAECgUJBwAAAA==.Wankz:BAAALgAECgkJEgAAAA==.Wankzerkin:BAAALgADCgEJAQAAAA==.Warriorguyes:BAABLgAECn8fAAIlAAkJtSKbBwDlAgAlAAkJtSKbBwDlAgAAAA==.',
We='Weyna:BAABLgAECn84AAMXAAgJ3hHVMgCsAQAXAAgJ3hHVMgCsAQAMAAYJVAmnTQDJAAABLgAFFAYJHwAZAO8UAA==.',
Wh='Whisperingei:BAAALgAECgYJCgAAAA==.Whomper:BAABLgAECn8dAAMbAAcJgRJ1CQDzAAAbAAUJkxV1CQDzAAAEAAcJZQm+CAC3AAAAAA==.Whpheonix:BAAALgADCgkJEAAAAA==.',
Wi='Wickedshadow:BAAALgAECgMJAwAAAA==.Widowx:BAACLgAFFH8JAAMWAAMJaw+4IACgAAAWAAMJaw+4IACgAAABAAEJEgEjjwAgAAAuAAQKfzUAAhYACQlGHTIEAO0BABYACQlGHTIEAO0BAAAA.Winfurdal:BAAALgADCggJCAAAAA==.',
Wo='Womphunt:BAABLgAECn8WAAIFAAcJlBqgPgDnAQAFAAcJlBqgPgDnAQABLgAECgkJLAAUABkhAA==.',
Wr='Wrandohunt:BAAALgAECgEJBAAAAA==.Wrandowdemon:BAAALgADCgcJBwAAAA==.Wreckitrandy:BAAALgAECgEJAQAAAA==.Wryn:BAAALgAECgkJEQABLgAFFAMJBQAGAPUQAA==.',
Wu='Wulyn:BAAALgAECggJEAAAAA==.',
Wy='Wylla:BAABLgAECn8YAAILAAcJvQ+oBgAxAQALAAcJvQ+oBgAxAQAAAA==.',
Xa='Xalethra:BAABLgAECn89AAICAAkJ8CQ7BQA0AwACAAkJ8CQ7BQA0AwAAAA==.Xaltheris:BAAALgAECgUJBgAAAA==.',
Xe='Xelha:BAAALgAECgYJBgAAAA==.Xenophobias:BAABLgAECn8aAAMcAAcJyBFECAAEAQAcAAcJyBFECAAEAQAGAAIJUgMdowEdAAAAAA==.',
Xh='Xhosen:BAABLgAFFH8HAAIGAAIJEhJ+bgB8AAAGAAIJEhJ+bgB8AAAAAA==.',
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
