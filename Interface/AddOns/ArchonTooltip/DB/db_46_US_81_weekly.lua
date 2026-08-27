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

local lookup = {'Shaman-Restoration','DemonHunter-Devourer','Druid-Restoration','Druid-Feral','Hunter-BeastMastery','Druid-Balance','Priest-Discipline','Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','DeathKnight-Unholy','Paladin-Retribution','Paladin-Protection','Priest-Shadow','DemonHunter-Vengeance','Paladin-Holy','Hunter-Marksmanship','Priest-Holy','DemonHunter-Havoc','Shaman-Elemental','Monk-Mistweaver','Warrior-Arms','Evoker-Preservation','Shaman-Enhancement','Druid-Guardian','DeathKnight-Frost','DeathKnight-Blood','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Rogue-Assassination','Warlock-Demonology','Mage-Frost','Warrior-Protection','Evoker-Augmentation','Warrior-Fury','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=46,date='2026-08-25',data={Aa='Aarmorr:BAABLgAECn9SAAIBAAkJmhk4FgCYAgABAAkJmhk4FgCYAgAAAA==.Aatus:BAAALgAECgcJDQAAAA==.',
Ab='Absoul:BAAALgAECgQJBwAAAA==.Abyssidia:BAAALgAECgMJAwAAAA==.',
Ac='Acinianis:BAAALgAECgEJAQAAAA==.Acinthos:BAAALgAECgQJBgAAAA==.',
Ad='Addah:BAAALgAECgQJBwAAAA==.Adiros:BAAALgADCgUJBQAAAA==.',
Ae='Aechelus:BAAALgADCgEJAQABLgAECggJFQACAAceAA==.Aedelas:BAAALgAECgIJBAAAAA==.Aeloriá:BAABLgAECn9PAAMDAAkJyCBxBwBAAwADAAkJyCBxBwBAAwAEAAEJFQGgOwAPAAAAAA==.Aelyra:BAAALgAECggJEgAAAA==.',
Ag='Agrosa:BAAALgAECgYJBgAAAA==.',
Ai='Aimeeiove:BAAALgAECgYJCgAAAA==.Airad:BAAALgADCgUJBgAAAA==.Airoldeel:BAAALgAECgIJAgAAAA==.',
Al='Alcarza:BAAALgAECgMJCAAAAA==.Alchon:BAABLgAECn8kAAIFAAkJ6xqGLwAeAgAFAAkJ6xqGLwAeAgAAAA==.Aldera:BAABLgAECn88AAIBAAkJwgm6EAAnAQABAAkJwgm6EAAnAQAAAA==.Aledish:BAAALgAECgEJAgAAAA==.Alexstrayza:BAAALgAECgMJAwAAAA==.Alista:BAAALgAECgYJCwAAAA==.Alladon:BAAALgADCgUJBQAAAA==.Allykat:BAABLgAECn9QAAMDAAgJRxmkAwAVAgADAAgJRxmkAwAVAgAGAAYJRxEIPwATAQAAAA==.Alorris:BAAALgAECgQJBgABLgAECgkJGQAHAFggAA==.Alunathsong:BAAALgADCgcJBwAAAA==.Alvagíngras:BAAALgAECgkJEAAAAA==.Alyra:BAAALgAECgYJBgAAAA==.',
Am='Amaith:BAACLgAFFH8KAAIIAAIJUw/LHgCNAAAIAAIJUw/LHgCNAAAuAAQKfyMAAggACQmnGz0BAJkCAAgACQmnGz0BAJkCAAAA.Amantillado:BAAALgAECgUJCAABLgAECggJGQAJAGIXAA==.Amata:BAAALgAECgUJCwAAAA==.Amelianne:BAAALgAECgcJEQAAAA==.Amiria:BAAALgAECgYJBgAAAA==.Ammastary:BAAALgAECgUJBwAAAA==.Ammonfrey:BAAALgAECgEJAQAAAA==.Amorfati:BAAALgAECgEJAQAAAA==.',
An='Ananiel:BAAALgADCgQJBQABLgAECgkJLwAKAA8bAA==.Andragos:BAAALgAECgQJCgAAAA==.Andrea:BAABLgAECn9KAAIEAAkJYR3oBACrAgAEAAkJYR3oBACrAgAAAA==.Andrelia:BAAALgAECgMJAwAAAA==.Angelec:BAAALgAECgEJAQAAAA==.Angelex:BAAALgAECgEJAQAAAA==.Anthria:BAAALgAECgcJEAAAAA==.',
Ao='Aoon:BAAALgAECgEJAQAAAA==.',
Ap='Apoleth:BAAALgADCgMJAwAAAA==.',
Aq='Aqules:BAAALgADCgEJAgAAAA==.',
Ar='Arand:BAAALgADCgIJAwAAAA==.Arcapeligo:BAAALgAECgEJAgAAAA==.Archonsfury:BAAALgAECggJDwAAAA==.Arilyn:BAAALgAECgMJAwAAAA==.Array:BAAALgAECgUJBQAAAA==.',
As='Asath:BAAALgAECgYJDAAAAA==.Ascended:BAAALgAECgEJAgABLgADCgkJCQALAAAAAA==.Asheye:BAAALgAECgkJCwABLgAFFAMJBQAMAPUQAA==.Ashogar:BAAALgAECgUJBQAAAA==.Ashuranadi:BAAALgADCgcJBwAAAA==.Askir:BAAALgADCgMJAwAAAA==.Asnew:BAAALgAECgkJEQAAAA==.Asura:BAAALgAECgkJEwAAAA==.Asyllaa:BAABLgAECn8eAAMNAAkJFx+LLABPAgANAAcJOyOLLABPAgAOAAYJ9hLNHwAWAQAAAA==.',
At='Athelstan:BAAALgADCgIJAgAAAA==.Atnawuerus:BAAALgAECgEJAQAAAA==.Atonement:BAABLgAECn8aAAMHAAkJJBqFFAA5AgAHAAgJNh2FFAA5AgAPAAQJLgkTcwBbAAABLgAFFAMJCAAQAOkhAA==.',
Au='Aumaril:BAABLgAECn8mAAMRAAgJ4herAwD+AQARAAgJ4herAwD+AQANAAgJBxntEgBLAQAAAA==.Auralynn:BAABLgAECn8rAAINAAkJEAp/kgBOAQANAAkJEAp/kgBOAQAAAA==.',
Av='Avathar:BAAALgAECgMJBgAAAA==.Averina:BAAALgAECgMJAwAAAA==.Averus:BAABLgAECn9SAAIGAAkJuhLJHQDaAQAGAAkJuhLJHQDaAQAAAA==.',
Az='Azariel:BAABLgAECn8+AAINAAkJ5BPmUwDOAQANAAkJ5BPmUwDOAQAAAA==.Azenwraith:BAAALgADCgkJCQAAAA==.Azuriah:BAABLgAECn9MAAMOAAkJ6B3/BQCLAgAOAAkJIB3/BQCLAgANAAEJXyHCTgFfAAAAAA==.',
Ba='Baane:BAAALgAECgUJCAABLgAECggJFAAHACANAA==.Babnik:BAEBLgAECn8YAAMFAAkJZBNyFQA4AQAFAAkJZBNyFQA4AQASAAIJPw0IMABYAAAAAA==.Bagel:BAACLgAFFH8eAAMRAAUJHCNeDQDhAQARAAUJHCNeDQDhAQANAAQJaQc8PACrAAAuAAQKfxkAAxEACAmCH1AmAPYBABEACAmCH1AmAPYBAA0AAQnkCrKpASsAAAAA.Baldwin:BAAALgAECgUJBQAAAA==.Ballbreaker:BAAALgAECgQJBAAAAA==.Baminenherb:BAAALgADCgUJBQAAAA==.Bazluz:BAAALgADCgIJAwAAAA==.',
Be='Bearbone:BAAALgAECgIJAwAAAA==.Bearlysoberr:BAAALgAECgUJBQAAAA==.Bedhead:BAABLgAECn9DAAQHAAkJpRdwEQBdAgAHAAkJ7BZwEQBdAgATAAMJFBx6VQDgAAAPAAEJKwrXjgAsAAAAAA==.Bedrocked:BAAALgAECgIJAwAAAA==.Belaim:BAAALgAECgIJAgAAAA==.Belovis:BAACLgAFFH8fAAINAAYJiCS1GQCkAQANAAYJiCS1GQCkAQAuAAQKfyYAAg0ACQk0JOgMACYDAA0ACQk0JOgMACYDAAAA.Berathor:BAAALgAECgkJEwAAAA==.Betsea:BAAALgAECgUJBQABLgAECgkJOgARAGYTAA==.',
Bi='Bidoof:BAABLgAECn86AAIUAAkJvBF8BQCIAQAUAAkJvBF8BQCIAQAAAA==.Bigblunt:BAAALgADCgcJEgAAAA==.Bigear:BAAALgAECgQJBAAAAA==.Bigjohnii:BAAALgADCgcJBwAAAA==.Birdi:BAAALgAECgEJAwAAAA==.Bitemarks:BAAALgADCgcJDgAAAA==.',
Bl='Blackcoat:BAAALgAECgYJDwAAAA==.Bluedragan:BAAALgAECgQJBAABLgAFFAMJCgAHALMRAA==.',
Bo='Boggrog:BAAALgAECgYJCQABLgAECgUJCwALAAAAAA==.Boghamut:BAAALgADCgcJBwABLgAECgUJCwALAAAAAA==.Bolz:BAAALgAECgMJAwAAAA==.Boosch:BAAALgADCgIJAgAAAA==.Boras:BAAALgAECgEJAQABLgAECggJGwACAMMYAA==.Bosshog:BAABLgAECn80AAIVAAkJpAvuNgBeAQAVAAkJpAvuNgBeAQAAAA==.Bowgobrr:BAABLgAECn8qAAMSAAgJ4xXlDgBvAQASAAgJ4xXlDgBvAQAFAAYJ2QpW3QCTAAABLgAFFAkJPgAFADQYAA==.',
Br='Braelyne:BAABLgAECn8WAAINAAYJdR3JXwDEAQANAAYJdR3JXwDEAQAAAA==.Brasnite:BAAALgADCgEJAQAAAA==.Brewrock:BAAALgAECgQJCAAAAA==.Brewtilus:BAAALgAECgQJBwAAAA==.Brolaf:BAAALgAECgUJBQAAAA==.Broseidon:BAAALgAECgcJEQAAAA==.Bryst:BAAALgADCgQJBAAAAA==.',
Bu='Buffsalot:BAAALgAECgUJDgAAAA==.Buffwarlock:BAAALgAECgcJBwAAAA==.Bullbatoo:BAAALgAECgEJAQAAAA==.Burlycheeks:BAABLgAECn85AAINAAkJPCCTGACwAgANAAkJPCCTGACwAgAAAA==.',
Ca='Calav:BAAALgAECgYJDAAAAA==.Caliista:BAAALgADCggJCAAAAA==.Carlitocool:BAAALgADCgIJAgAAAA==.Carraxus:BAAALgAECgQJDAAAAA==.Cassidyn:BAAALgADCgcJCAAAAA==.Castle:BAABLgAECn8aAAMNAAgJ1h09bwCQAQANAAcJbhw9bwCQAQARAAYJZwkZDgDOAAAAAA==.Catsinhats:BAAALgAECgUJBAABLgAFFAQJFAAMAC8OAA==.Catsneverdie:BAAALgAFFAEJAQABLgAFFAQJFAAMAC8OAA==.Catzinhatz:BAABLgAECn8YAAICAAcJAgq/jgADAQACAAcJAgq/jgADAQABLgAFFAQJFAAMAC8OAA==.',
Ce='Cecelya:BAABLgAECn9AAAQTAAkJ5RlLFwAUAgATAAkJ5RlLFwAUAgAPAAcJNhGCNABGAQAHAAMJUw1iXACOAAAAAA==.Celerian:BAAALgAECgQJBAAAAA==.Celibate:BAAALgAECgUJBgAAAA==.Celothor:BAAALgADCgYJBgAAAA==.Celticmoon:BAAALgADCgQJBAAAAA==.',
Ch='Cherlia:BAABLgAECn8cAAIVAAYJIhO2RQAyAQAVAAYJIhO2RQAyAQABLgAECgkJHgAUAFciAA==.Chillykiller:BAAALgAECgYJBwABLgAECgkJHgAUAFciAA==.Chiva:BAAALgAECgQJBAABLgAFFAMJBwABAGAPAA==.Chivactdl:BAAALgAECgMJBAABLgAFFAMJBwABAGAPAA==.Chivalt:BAAALgAECgEJAQABLgAFFAMJBwABAGAPAA==.Chonch:BAAALgAECgIJAgAAAA==.Chozen:BAAALgAECggJCwAAAA==.Chunknoriss:BAABLgAECn8vAAMWAAYJYiD3HQApAgAWAAYJYiD3HQApAgAJAAMJWwWbdwBhAAABLgAFFAMJBwABAGAPAA==.',
Ci='Cigarettes:BAABLgAECn8XAAIXAAYJsRW2BwDyAAAXAAYJsRW2BwDyAAAAAA==.',
Cl='Claudiuss:BAAALgAECgYJDAABLgAFFAMJCgABAGcPAA==.Clurefu:BAABLgAECn84AAMWAAkJvCEQBQBaAwAWAAkJvCEQBQBaAwAJAAMJ5BZVWACuAAABLgAFFAMJDQADAK8dAA==.Clurelock:BAACLgAFFH8NAAIDAAMJrx0/EgD7AAADAAMJrx0/EgD7AAAuAAQKf0AAAgMACQn6Ii4EAHsDAAMACQn6Ii4EAHsDAAAA.Cluremage:BAAALgAECgYJEQAAAA==.Clurethyr:BAABLgAECn8rAAIYAAgJzB+JAADaAgAYAAgJzB+JAADaAgABLgAFFAMJDQADAK8dAA==.',
Co='Cobblestone:BAAALgAECgIJAgAAAA==.Codenameknd:BAAALgAECgIJAgAAAA==.Comsuck:BAAALgAECgcJEQAAAA==.Conchobhar:BAABLgAECn8VAAIWAAkJlBoMGgBHAgAWAAkJlBoMGgBHAgAAAA==.Constella:BAAALgADCgYJCQAAAA==.Coppertan:BAAALgAECgMJBQAAAA==.Coralyne:BAAALgADCgEJAQAAAA==.Corrosion:BAABLgAECn8wAAIZAAkJUx5gAQAyAgAZAAkJUx5gAQAyAgAAAA==.',
Cr='Crazyshammy:BAAALgAECgkJEgAAAA==.Crommash:BAAALgAECgcJCgAAAA==.Crono:BAAALgAECgQJCQAAAA==.Crunchynuget:BAABLgAECn8pAAINAAkJbSArBACaAgANAAkJbSArBACaAgABLgAFFAcJGwANAK0dAA==.',
Ct='Cthuwu:BAAALgAECgMJAwABLgAFFAcJFAAFAN8VAA==.',
Cu='Cujotaro:BAAALgAECgEJAgAAAA==.Cumberdale:BAAALgAECgUJBQAAAA==.',
Cv='Cvhamster:BAAALgAECgQJCgAAAA==.',
Cy='Cybeast:BAABLgAECn81AAMEAAkJkh54BAC4AgAEAAkJhB54BAC4AgAaAAUJFRjEBQBVAQAAAA==.Cynortas:BAAALgAECgIJBgAAAA==.',
Da='Daciana:BAABLgAECn8iAAIFAAkJvRLgFgArAQAFAAkJvRLgFgArAQAAAA==.Dados:BAABLgAECn8wAAMTAAkJXh5tDgCBAgATAAkJXh5tDgCBAgAPAAEJsBRKgAA9AAAAAA==.Daeghun:BAAALgAECgIJBQAAAA==.Dahleigh:BAAALgADCgkJDQAAAA==.Dakanar:BAAALgAECgQJCgAAAA==.Dambrien:BAAALgAECgUJBQAAAA==.Daravus:BAAALgAECgUJCAAAAA==.Darkfox:BAAALgAECgEJAQAAAA==.Darkhazel:BAAALgAECgEJAQAAAA==.Darkkromdor:BAABLgAECn8zAAINAAkJtR/SFwC0AgANAAkJtR/SFwC0AgAAAA==.Darloct:BAAALgAECggJEwAAAA==.Dazzlor:BAAALgADCggJCAAAAA==.',
De='Deadelff:BAABLgAECn8kAAMCAAgJ2hZHYwBhAQAUAAYJexvxJwCDAQACAAgJQg9HYwBhAQAAAA==.Deadholypaly:BAAALgADCgEJAwAAAA==.Deadlifts:BAAALgAECgQJCQAAAA==.Deadlighted:BAAALgADCgcJDgABLgAECggJJAACANoWAA==.Deadslinger:BAAALgADCgYJDAAAAA==.Deadtotem:BAAALgADCgkJCQABLgAECggJJAACANoWAA==.Deammon:BAAALgAECgEJAQAAAA==.Deathcat:BAACLgAFFH8UAAIMAAQJLw6MTQDAAAAMAAQJLw6MTQDAAAAuAAQKfzsAAgwACQmjFgc4AB8CAAwACQmjFgc4AB8CAAAA.Deathkiss:BAAALgAECgYJEgAAAA==.Deathpheonix:BAAALgAECgQJBwAAAA==.Deathrat:BAAALgADCgUJBgAAAA==.Deathrixx:BAABLgAFFH8RAAQMAAUJZx4JVABKAQAMAAUJQh4JVABKAQAbAAIJhB3QHACdAAAcAAEJIBhWPABEAAAAAA==.Deathshadowx:BAAALgAECgYJDAAAAA==.Dedbull:BAAALgAECgEJAQAAAA==.Delryth:BAAALgAECgQJBAAAAA==.Demoodius:BAAALgAECgEJAQAAAA==.Denajah:BAAALgAECgIJAgAAAA==.',
Df='Dfault:BAAALgADCgEJAQAAAA==.',
Di='Discharged:BAAALgAECgQJBAABLgAECggJGQAJAGIXAA==.',
Dk='Dkdeathblade:BAAALgAECgEJAQAAAA==.Dkpheonix:BAABLgAECn80AAIPAAkJ6xWoGAABAgAPAAkJ6xWoGAABAgAAAA==.',
Do='Dolemite:BAABLgAECn9HAAMWAAcJHhYdLwC/AQAWAAcJHhYdLwC/AQAJAAcJcRmSAwCyAQAAAA==.Donalbain:BAACLgAFFH8KAAIBAAMJZw+8UwCqAAABAAMJZw+8UwCqAAAuAAQKfzAAAgEACQkCHlUDAIUCAAEACQkCHlUDAIUCAAAA.Donninban:BAAALgADCgIJAgABLgADCgIJAgALAAAAAA==.Dotdotgoose:BAAALgAECgQJCAAAAA==.',
Dr='Draconz:BAAALgAECgIJAgABLgAECgcJEwALAAAAAA==.Draganpriest:BAABLgAFFH8KAAIHAAMJsxHyHwCQAAAHAAMJsxHyHwCQAAAAAA==.Draganussy:BAAALgADCgEJAQABLgAFFAMJCgAHALMRAA==.Draggo:BAAALgAECgEJAQAAAA==.Drakkira:BAAALgADCgYJBgAAAA==.Draxon:BAAALgAECgEJAQAAAA==.Dremar:BAABLgAECn8gAAMdAAkJ2BArBAAvAQAdAAgJkQ8rBAAvAQAeAAYJRAyRGQDXAAAAAA==.Druc:BAAALgAECgEJAgAAAA==.',
Du='Durock:BAAALgAECgMJBAAAAA==.',
Dy='Dynaris:BAAALgADCgMJAwAAAA==.Dynera:BAAALgAECgQJBAAAAA==.',
Ei='Eianna:BAAALgAECgEJAQAAAA==.',
El='Elcachazo:BAAALgAECgIJAgAAAA==.Eldinn:BAAALgADCgcJBgAAAA==.Eleanni:BAAALgAECgQJBAAAAA==.Elenora:BAAALgAECgMJAwAAAA==.Elidor:BAABLgAECn8XAAQGAAgJNwseUADNAAAGAAYJkAweUADNAAADAAQJJxAsFQBvAAAaAAQJbQIYIAA7AAAAAA==.Ellalangley:BAAALgAECgIJAwABLgAFFAMJBQAMAPUQAA==.Elthelas:BAAALgADCgEJAQAAAA==.Eluneatic:BAAALgADCggJCgAAAA==.Elyssaris:BAABLgAECn84AAIcAAkJ4xoyDgAnAgAcAAkJ4xoyDgAnAgAAAA==.Elzulkin:BAAALgADCgcJCgAAAA==.',
Em='Emmdeath:BAABLgAECn8YAAIMAAYJ7QNWDgGaAAAMAAYJ7QNWDgGaAAAAAA==.Emmils:BAABLgAECn8+AAIGAAkJfA1uKgCBAQAGAAkJfA1uKgCBAQAAAA==.Emìly:BAABLgAECn9VAAQJAAkJGiQiAwAyAwAJAAkJGiQiAwAyAwAWAAkJCxaKHwAeAgAKAAUJRRUqRgDiAAAAAA==.',
En='Enderelvarg:BAABLgAFFH8FAAIfAAUJbw9TBQARAQAfAAUJbw9TBQARAQAAAA==.Endmicrobuys:BAAALgADCgUJBQAAAA==.Entaria:BAACLgAFFH8GAAINAAQJmhmFMQBOAQANAAQJmhmFMQBOAQAuAAQKf0EABA0ACQk7IYMOAPICAA0ACQk7IYMOAPICAA4ABwkxH24NAO4BABEABgm1DGJbAMgAAAAA.',
Eo='Eox:BAAALgADCgMJAwAAAA==.',
Ep='Episkey:BAABLgAECn8gAAMGAAkJMhKOJgCZAQAGAAkJMhKOJgCZAQADAAQJdRcgYQASAQAAAA==.',
Er='Erindaglaze:BAAALgADCgQJBQAAAA==.Erissae:BAAALgADCgEJAgAAAA==.Eropor:BAABLgAECn8iAAMWAAYJexPyQQBlAQAWAAYJexPyQQBlAQAJAAMJYQbMigBHAAABLgAFFAQJGAADAEIRAA==.Eroversion:BAACLgAFFH8YAAMDAAQJQhFrMwDgAAADAAQJQhFrMwDgAAAGAAEJtwG5NQAfAAAuAAQKf1YABQMACQlCHq8XAIkCAAMACQlCHq8XAIkCAAYABAkIFj5UANUAAAQAAwm4DUszAJEAABoAAQkAAFWVAAAAAAAA.Eroward:BAAALgAECgcJEwABLgAFFAQJGAADAEIRAA==.',
Es='Esmay:BAABLgAECn8fAAIVAAkJHRRNIADhAQAVAAkJHRRNIADhAQAAAA==.Eso:BAAALgADCgYJCwAAAA==.',
Et='Ethren:BAABLgAECn9RAAIgAAkJ2RgJBABeAgAgAAkJ2RgJBABeAgAAAA==.',
Eu='Eudeyrn:BAAALgAECgYJAwAAAA==.',
Ev='Evilrepu:BAAALgAECgEJAQAAAA==.',
Ey='Eyebrows:BAAALgAECgIJAgAAAA==.',
Ez='Ezikarridge:BAAALgAECgIJAgAAAA==.',
Fa='Faker:BAAALgADCgEJAQAAAA==.Falcone:BAAALgAECgMJBgAAAA==.',
Fe='Felbolter:BAABLgAFFH8GAAIeAAQJaxCqAwAdAQAeAAQJaxCqAwAdAQAAAA==.Feliri:BAAALgAECggJEgAAAA==.',
Fi='Fiddlefaddle:BAAALgAFFAEJAQAAAA==.Filgulfin:BAABLgAECn9bAAMFAAkJBCC8EADLAgAFAAkJBCC8EADLAgASAAgJgRDREwAkAQAAAA==.Finkate:BAABLgAECn8XAAIFAAgJHA4FYwB/AQAFAAgJHA4FYwB/AQAAAA==.Firebad:BAABLgAECn8wAAMeAAkJpxy5AgCFAgAeAAkJpxy5AgCFAgAhAAYJHwrG5ACTAAAAAA==.Firebringer:BAABLgAECn9VAAICAAkJ9A7jSgCmAQACAAkJ9A7jSgCmAQAAAA==.Fistokaestey:BAAALgADCgkJEgABLgAECgkJIwAiANUXAA==.',
Fl='Flaakk:BAAALgADCgcJBwAAAA==.Flamehunter:BAABLgAECn8iAAMCAAkJMRqEHACnAgACAAkJcRmEHACnAgAUAAcJLRdgJACaAQAAAA==.Flo:BAABLgAECn9aAAMPAAkJhxwZCwCeAgAPAAkJhxwZCwCeAgATAAMJSAcyWAB5AAAAAA==.Floki:BAABLgAECn8UAAIjAAkJqhJnHQBKAQAjAAkJqhJnHQBKAQAAAA==.Flora:BAAALgAECgQJBAAAAA==.Flowing:BAABLgAECn8wAAIkAAkJyxnGAgC9AQAkAAkJyxnGAgC9AQAAAA==.',
Fo='Foods:BAACLgAFFH8dAAMlAAMJiRPHHQC9AAAlAAMJiRPHHQC9AAAjAAIJBgtnGABgAAAuAAQKf4gABCUACQm1HssBAKECACUACQm1HssBAKECACMACAlkFbkEAFsBABcAAwnoDE0wAHUAAAAA.Foofsmash:BAAALgADCgUJBgAAAA==.',
Fr='Fripouille:BAAALgADCgMJAwAAAA==.',
Fu='Fustín:BAAALgAECgYJEgAAAA==.Fuzzyewok:BAAALgAECgYJEwAAAA==.',
['Fø']='Føøds:BAAALgADCgMJAwAAAA==.',
Ga='Gaboo:BAAALgAECgkJEwAAAA==.Galangal:BAAALgAECgIJAgAAAA==.Garfman:BAAALgAFFAEJAQAAAA==.Garthrall:BAAALgAECgEJAQAAAA==.',
Gb='Gb:BAACLgAFFH8HAAIRAAYJExDZHgAmAQARAAYJExDZHgAmAQAuAAQKfxUAAhEACAnpHYUSAH0CABEACAnpHYUSAH0CAAEuAAUUBAkNAA8A8hoA.',
Gh='Ghostinhale:BAABLgAECn8dAAIMAAcJ2RbwEQApAQAMAAcJ2RbwEQApAQAAAA==.',
Gi='Gibbshole:BAAALgADCgcJBwAAAA==.Gilorion:BAABLgAECn8XAAIFAAkJ7RbnMgARAgAFAAkJ7RbnMgARAgAAAA==.',
Gl='Glasgoww:BAAALgAECgYJCQABLgAFFAMJCgABAGcPAA==.Gløck:BAAALgAECgIJAgAAAA==.',
Gn='Gnibat:BAAALgAECgQJBwAAAA==.Gnomerlicous:BAAALgADCgkJCQAAAA==.',
Go='Goburina:BAACLgAFFH8VAAMBAAQJohXVHgDbAAABAAQJohXVHgDbAAAVAAEJ2wHLQgAjAAAuAAQKfxgAAgEACQlaC1M9AIwBAAEACQlaC1M9AIwBAAAA.Golias:BAAALgADCgEJAQAAAA==.Gonahrhea:BAAALgAECgEJAQAAAA==.',
Gr='Grenache:BAAALgAECgcJCAABLgAECgcJCAALAAAAAA==.Grievo:BAAALgAECgYJCQAAAA==.Grimdawn:BAAALgAFFAEJAQAAAA==.Grimfist:BAAALgAECgMJAwAAAA==.Grimtankdrud:BAAALgAECgEJAQABLgAECggJGwAQAOsPAA==.Grinnir:BAAALgAECgQJBgABLgAECggJGwACAMMYAA==.',
Gu='Guildenstern:BAAALgADCgUJBQABLgAFFAMJCgABAGcPAA==.Gulpron:BAAALgAECgcJCwAAAA==.',
Gy='Gypsiey:BAAALgAECgUJBQAAAA==.',
['Gí']='Gímlí:BAACLgAFFH8LAAIFAAMJABffNwDLAAAFAAMJABffNwDLAAAuAAQKfzgAAgUACQm8HiQdAHYCAAUACQm8HiQdAHYCAAAA.',
Ha='Halcyndraag:BAABLgAECn9SAAQkAAkJZxUrIQDQAQAkAAcJaxUrIQDQAQAfAAMJwBcBGgCBAAAYAAEJPQJWRAAeAAAAAA==.Handbannana:BAAALgAECgQJBAAAAA==.Handsome:BAAALgAECgcJDAABLgAECgkJGQAPADQJAA==.Happydk:BAACLgAFFH8RAAMMAAQJniCPPgB6AQAMAAQJniCPPgB6AQAcAAMJKRHrLACVAAAuAAQKfygAAwwACQkdI2MXALoCAAwACQlaIWMXALoCABwABwlKGSMnABsBAAAA.Hartu:BAABLgAECn9NAAIjAAkJfxTyDwDpAQAjAAkJfxTyDwDpAQAAAA==.Harukasan:BAAALgADCgIJAgAAAA==.Hashpipe:BAAALgADCgMJAwAAAA==.Hazl:BAAALgAECgMJBAAAAA==.',
He='Healortank:BAAALgAECgEJAQAAAA==.Healsofpain:BAAALgADCgYJBgAAAA==.Healtardo:BAAALgAFFAIJAgAAAA==.Heiro:BAAALgAFFAEJAQABLgAFFAUJDAAYAEQIAA==.Hellankeller:BAAALgAECgQJBwAAAA==.Hemic:BAACLgAFFH8TAAIIAAMJMB/TEgDtAAAIAAMJMB/TEgDtAAAuAAQKfzQAAwgACQlGI18FAN0CAAgACQlGI18FAN0CACAABAnwGhUQACMBAAAA.Hemmorage:BAAALgAECgYJCgABLgAFFAMJBQAMAPUQAA==.Hemogobblin:BAAALgAECgQJBAAAAA==.Herbalmist:BAAALgAECgYJDAAAAA==.',
Hi='Higag:BAAALgADCgQJBAAAAA==.Hinaba:BAAALgADCgMJAwAAAA==.Hippypally:BAAALgADCgEJAQAAAA==.Hircine:BAAALgAECgQJBQAAAA==.',
Ho='Holysea:BAAALgAECgYJDAABLgAECgkJOgARAGYTAA==.Horatio:BAAALgAECgEJAQABLgAFFAMJCgABAGcPAA==.',
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
Is='Isam:BAAALgADCgYJBgAAAA==.Isamidor:BAACLgAFFH8QAAIFAAYJlBsAKABnAQAFAAYJlBsAKABnAQAuAAQKfxwAAgUACQmXI+cEAD8DAAUACQmXI+cEAD8DAAAA.Ismokeu:BAACLgAFFH8aAAMTAAQJpBhWCwD5AAATAAQJbxdWCwD5AAAHAAQJMgr1FwDIAAAuAAQKfzoAAhMACQmrGZ4NAIwCABMACQmrGZ4NAIwCAAAA.Ismyn:BAAALgAECgYJBwAAAA==.',
It='Itskemba:BAAALgADCgYJBgAAAA==.',
Iy='Iyania:BAAALgADCgIJAgAAAA==.',
Iz='Izayoi:BAAALgADCgcJCQAAAA==.',
Ja='Jackoneal:BAABLgAECn8lAAINAAkJYggYpwAtAQANAAkJYggYpwAtAQAAAA==.Jalidelo:BAABLgAECn9KAAMHAAkJFR6cCADrAgAHAAkJFR6cCADrAgATAAEJ5gZihgAqAAAAAA==.Jaliwind:BAAALgADCgkJCQAAAA==.Jayan:BAAALgAECgEJAQAAAA==.',
Je='Jenifurr:BAAALgADCgIJAgAAAA==.Jenyx:BAAALgAECgUJCwAAAA==.',
Ji='Jimbowaboki:BAAALgAECgEJAQAAAA==.',
Jo='Johan:BAABLgAECn8eAAIhAAkJMhqFLAAnAgAhAAkJMhqFLAAnAgAAAA==.Jokers:BAABLgAECn8jAAMjAAYJXBUSCADaAAAlAAUJ4g/8WQDoAAAjAAYJShQSCADaAAAAAA==.Jokersfists:BAABLgAECn8XAAICAAYJVg85GwCxAAACAAYJVg85GwCxAAAAAA==.Joranbragi:BAABLgAECn8yAAMNAAkJOwyPGQARAQANAAgJ1QuPGQARAQAOAAMJjAhYEABkAAAAAA==.Jordanjr:BAAALgAECggJEQAAAA==.Jormun:BAAALgADCgEJAQAAAA==.Joshy:BAABLgAECn8dAAIdAAYJsRCBDgBJAQAdAAYJsRCBDgBJAQAAAA==.Jotoonice:BAABLgAECn8aAAIiAAgJjBVjYQC9AQAiAAgJjBVjYQC9AQAAAA==.',
Jt='Jtoothaordan:BAACLgAFFH8YAAQmAAcJexbcCgDpAAAmAAUJzBPcCgDpAAASAAMJsg0uLQBWAAAFAAIJAwgNqwBCAAAuAAQKfy4ABCYACAn9Hw8UAAUCABIACAn9F60gACACACYABgkaJA8UAAUCAAUAAglIIaDPAKsAAAAA.',
Ju='Juglfhednar:BAAALgADCgEJAQAAAA==.Jules:BAAALgAECgUJBQAAAA==.Justbob:BAAALgAECgUJBgAAAA==.',
['Jú']='Júgg:BAAALgAECgQJBgAAAA==.',
Ka='Kaachow:BAABLgAECn8uAAIDAAkJZR+DCQAiAwADAAkJZR+DCQAiAwAAAA==.Kaana:BAABLgAECn9QAAIFAAkJ7xmlHwBpAgAFAAkJ7xmlHwBpAgAAAA==.Kaelenil:BAAALgAECgEJAQAAAA==.Kaestey:BAAALgAECggJDQABLgAECgkJIwAiANUXAA==.Kairis:BAAALgAECgYJCQABLgAFFAUJKAADABYkAA==.Kalia:BAAALgAECgEJAQABLgAECgkJOAAcAOMaAA==.Kallista:BAAALgADCgEJAQAAAA==.Kanoalandiwa:BAAALgAECgEJAQABLgAFFAMJCwAFAAAXAA==.Karthagon:BAABLgAECn8tAAINAAkJfxxiBACQAgANAAkJfxxiBACQAgAAAA==.Karungash:BAACLgAFFH8LAAMhAAQJqgoMZAD/AAAhAAQJqgoMZAD/AAAeAAEJVQE+GwA+AAAuAAQKfx0AAyEACAm1Id4QAPMCACEACAm1Id4QAPMCAB4AAgkTEk1SAHcAAAAA.Karva:BAABLgAECn8kAAIQAAkJzBqWBgAqAgAQAAkJzBqWBgAqAgAAAA==.Karvy:BAABLgAECn8kAAIaAAgJXB4LBACcAQAaAAgJXB4LBACcAQABLgAECgkJJAAQAMwaAA==.Kash:BAAALgADCgUJBQABLgAFFAUJEwAEACYlAA==.Kayzer:BAAALgADCgYJGAAAAA==.',
Ke='Kelonaar:BAACLgAFFH8bAAIVAAYJ9x/gDABxAQAVAAYJ9x/gDABxAQAuAAQKfygAAxUACQksIqEWADECABUACQksIqEWADECABkAAgn1Gg45AEoAAAAA.Kelya:BAAALgAECgUJBQABLgAFFAYJGwAVAPcfAA==.Kerrie:BAAALgADCgEJAQAAAA==.',
Kh='Kharys:BAAALgAECgUJDAAAAA==.Khthonious:BAABLgAECn8VAAICAAcJBx4TOwDbAQACAAcJBx4TOwDbAQAAAA==.',
Ki='Kibblsncrits:BAAALgAECgIJAwABLgAECgkJEgALAAAAAA==.Kickingdonut:BAACLgAFFH8FAAIJAAMJNx8sHADtAAAJAAMJNx8sHADtAAAuAAQKfywAAwkACAk7IxkJAOcCAAkACAk7IxkJAOcCAAoABgn1GUI3AG4BAAAA.Killerhottie:BAAALgAECgEJAQAAAA==.Killermoomoo:BAAALgAECgUJCwAAAA==.Kinoh:BAAALgADCgkJEAAAAA==.Kittykarma:BAAALgAECgUJBQAAAA==.',
Kl='Kloverr:BAAALgAECgIJAgAAAA==.Klub:BAAALgADCgYJBgAAAA==.',
Ko='Kollita:BAAALgAECgEJAQAAAA==.Komatsu:BAAALgAECgEJAQAAAA==.Kombatkarl:BAAALgAECgEJAQAAAA==.Koramere:BAAALgADCgcJBwAAAA==.',
Kr='Kretaios:BAAALgADCgQJBAAAAA==.Kromir:BAAALgAECgQJBwAAAA==.Kromnar:BAAALgADCgEJAQAAAA==.Kronixrage:BAAALgAECgYJCwAAAA==.Kronn:BAAALgAECgYJBwAAAA==.Krooler:BAAALgAECgQJCAAAAA==.Krum:BAACLgAFFH8gAAINAAUJaR8DKQBnAQANAAUJaR8DKQBnAQAuAAQKfx4AAg0ACAmsHYRRANQBAA0ACAmsHYRRANQBAAAA.',
Ku='Kungfoumoo:BAAALgAECgEJAQAAAA==.',
La='Ladgarkk:BAAALgADCggJFQAAAA==.Lanval:BAABLgAECn9eAAINAAkJgBtIIgB9AgANAAkJgBtIIgB9AgAAAA==.Lardend:BAABLgAECn8bAAIUAAgJsAkjCwDrAAAUAAgJsAkjCwDrAAAAAA==.Latinlover:BAAALgADCgEJAQAAAA==.Laurian:BAAALgADCgcJDwAAAA==.Laurì:BAAALgAECgMJBQABLgAECgkJVQAJABokAA==.',
Le='Leaky:BAAALgAECgIJBAAAAA==.Leetah:BAACLgAFFH8dAAIaAAMJ0R/KCAAIAQAaAAMJ0R/KCAAIAQAuAAQKf5EAAxoACQlhI44AACoDABoACQlhI44AACoDAAQABQkuIGcDAHIBAAAA.Leftblank:BAABLgAECn8UAAMMAAgJOAlgFwD4AAAMAAgJOAlgFwD4AAAbAAQJPAPcLgBkAAAAAA==.Legitimas:BAAALgAECgEJAQAAAA==.Lemix:BAAALgAECgMJDAAAAA==.Letmetameyou:BAAALgAECgYJBgAAAA==.',
Li='Liasong:BAAALgADCgMJAwAAAA==.Lilyandra:BAAALgADCgkJEAAAAA==.Lilyara:BAAALgADCgIJAgAAAA==.Lilyoptra:BAABLgAECn8VAAIhAAcJKwPqMABGAAAhAAcJKwPqMABGAAABLgAECgkJFwAGADcLAA==.Lindrael:BAAALgADCgEJAQAAAA==.Liszt:BAAALgAECgYJBgAAAA==.Litallya:BAAALgAECggJDQAAAA==.Littletush:BAABLgAECn8dAAIFAAkJNAw9DwCAAQAFAAkJNAw9DwCAAQAAAA==.Livingdemon:BAAALgAECgUJDwAAAA==.',
Lm='Lminus:BAAALgAECgYJEgAAAA==.',
Lo='Lockolus:BAAALgAECgMJAwAAAA==.Lockpockets:BAAALgADCgEJAQAAAA==.Longshot:BAAALgAECgIJAgABLgAECgUJCwALAAAAAA==.Lootie:BAAALgAECggJDgAAAA==.Loriane:BAAALgAECgUJCAABLgAECgkJKAADAAIgAA==.Lorianth:BAAALgADCgcJDgAAAA==.Lotharbacco:BAAALgAECgMJAwAAAA==.Lovegood:BAAALgADCgEJAQAAAA==.Loveisbeauty:BAAALgAECgUJBwAAAA==.Lowki:BAAALgAECgEJAgAAAA==.',
Lu='Lundigras:BAAALgADCgkJCQAAAA==.',
Ly='Lychi:BAAALgAECgYJDAAAAA==.Lylora:BAACLgAFFH8oAAIDAAUJFiS+BgACAgADAAUJFiS+BgACAgAuAAQKf08AAgMACQm8JOIBALoDAAMACQm8JOIBALoDAAAA.Lysera:BAAALgADCgMJAwAAAA==.',
['Lê']='Lêmonaide:BAABLgAECn8tAAMTAAkJTQ+oJgCQAQATAAkJTQ+oJgCQAQAPAAUJAgXEagBzAAAAAA==.',
Ma='Madesh:BAABLgAECn9LAAMQAAkJYxv+BQA8AgAQAAkJtxj+BQA8AgACAAkJZBozKAAqAgAAAA==.Madman:BAABLgAECn8vAAIWAAkJTA9jOQCMAQAWAAkJTA9jOQCMAQAAAA==.Maelle:BAABLgAECn9SAAINAAkJ2iJZDAACAwANAAkJ2iJZDAACAwAAAA==.Magekaestey:BAABLgAECn8jAAIiAAkJ1RfHPAAnAgAiAAkJ1RfHPAAnAgAAAA==.Majandra:BAAALgAECgUJDAAAAA==.Malala:BAAALgAECgcJDQABLgAFFAIJFQATAD4dAA==.Malyndra:BAABLgAECn8zAAMUAAkJNB0EDwA1AgAUAAkJixsEDwA1AgAQAAYJ9hksDgBvAQAAAA==.Malyssa:BAAALgADCgIJAgAAAA==.Marianne:BAAALgADCgYJBwAAAA==.Marle:BAAALgAECgEJBAAAAA==.Marvolt:BAABLgAECn8YAAIhAAgJcA0RbQBiAQAhAAgJcA0RbQBiAQAAAA==.Masy:BAAALgAECgEJAQAAAA==.',
Mc='Mcrae:BAAALgAECgYJBwAAAA==.',
Md='Md:BAAALgAECgEJAgAAAA==.',
Me='Medrare:BAAALgAECgEJAQAAAA==.Meekastraza:BAAALgAECgIJAgAAAA==.Melon:BAAALgADCgEJAQABLgAECgkJDQALAAAAAA==.Meriam:BAAALgAECgEJAgABLgAFFAMJBQAMAPUQAA==.Merlot:BAAALgAECgcJCAAAAA==.Mesmash:BAABLgAECn8wAAIjAAkJniFHBADjAgAjAAkJniFHBADjAgAAAA==.Metadk:BAAALgAECgQJCAABLgAECggJGQAJAGIXAA==.Metahunt:BAAALgAECgIJAgABLgAECggJGQAJAGIXAA==.Metamasters:BAAALgAECgQJBgABLgAECggJGQAJAGIXAA==.Metatotem:BAAALgAECgIJBAABLgAECggJGQAJAGIXAA==.Metavoker:BAAALgAECgUJBQABLgAECggJGQAJAGIXAA==.',
Mi='Mialtaa:BAABLgAECn8vAAIKAAkJDxvjCwB2AgAKAAkJDxvjCwB2AgAAAA==.Midgiit:BAAALgAECgUJBQABLgAFFAMJBQAMAPUQAA==.Miink:BAAALgADCgYJBgAAAA==.Milkurs:BAAALgAECgQJBwAAAA==.Miniborg:BAABLgAECn8iAAIFAAkJ+xo5HAB7AgAFAAkJ+xo5HAB7AgABLgAFFAcJGwANAK0dAA==.Minidude:BAAALgAECgYJEAAAAA==.Minionghost:BAAALgADCggJCAAAAA==.Miyuki:BAAALgAECgQJBgAAAA==.Mizzen:BAAALgAFFAEJAQAAAA==.',
Mj='Mjolnir:BAAALgAECgcJBgAAAA==.',
Mo='Moejojojo:BAABLgAECn8WAAIJAAkJ0yF4DwBTAgAJAAkJ0yF4DwBTAgAAAA==.Monkter:BAABLgAECn8ZAAQJAAgJYheyHADJAQAJAAgJYheyHADJAQAWAAEJ/gbfbgAmAAAKAAEJfggUoAAiAAAAAA==.Monsignore:BAAALgADCgQJBAAAAA==.Moofasaha:BAAALgAECgkJEAAAAA==.Mooheals:BAAALgADCgEJAQAAAA==.Moonk:BAAALgAECgcJBQAAAA==.Morangia:BAAALgADCgcJBwAAAA==.Morbus:BAAALgAECgUJBQAAAA==.Morduos:BAAALgAECgcJBgABLgAECggJFQACAAceAA==.Morog:BAACLgAFFH8WAAMmAAYJURpxBQC4AQAmAAYJURpxBQC4AQAFAAEJ0w1tqwBCAAAuAAQKfykABBIACQmpGyMsAM0BABIABgmOHSMsAM0BAAUABgkbGq0/ALABACYABgnqE/UpAFEBAAAA.Morragan:BAAALgAECgQJBQAAAA==.Mortegom:BAAALgADCgcJBwAAAA==.Moráthi:BAAALgADCgcJBwAAAA==.',
Mu='Mulvan:BAAALgAECggJEQAAAA==.',
My='Myinja:BAAALgAECgQJCAABLgAECggJGQAJAGIXAA==.Myrddinwyllt:BAAALgAECgYJDAAAAA==.Myzac:BAAALgAECgEJAQAAAA==.',
Mz='Mzharipants:BAAALgADCgIJAgAAAA==.',
Na='Naadra:BAAALgAECgEJAQAAAA==.Nabû:BAAALgADCggJDwAAAA==.Naema:BAAALgAECggJDgAAAA==.Nalid:BAACLgAFFH8TAAIEAAUJJiW2AgCqAQAEAAUJJiW2AgCqAQAuAAQKf0QAAwQACQnAJkAAAIwDAAQACQnAJkAAAIwDAAYAAQmuAl6mABsAAAAA.Nanarus:BAACLgAFFH8VAAITAAIJPh2dEgCPAAATAAIJPh2dEgCPAAAuAAQKf10AAxMACQnTINMAAC0DABMACQnTINMAAC0DAA8ABgnkA+VWALgAAAAA.Nanosec:BAAALgAECgEJAQAAAA==.Nansea:BAAALgAECgEJAgAAAA==.Nashalie:BAABLgAECn80AAIhAAkJsR5IAwBrAgAhAAkJsR5IAwBrAgAAAA==.Natedawg:BAAALgAECgUJCQAAAA==.',
Ne='Neezzdutzz:BAAALgAECgQJBAAAAA==.Nefele:BAABLgAECn8hAAIBAAkJ5RUWIwA8AgABAAkJ5RUWIwA8AgAAAA==.Nepheli:BAACLgAFFH8GAAICAAMJUxefVgDrAAACAAMJUxefVgDrAAAuAAQKf00AAgIACQlrJF4DAFIDAAIACQlrJF4DAFIDAAAA.Newrhu:BAAALgAECgYJBwAAAA==.Nexbasia:BAACLgAFFH8YAAIEAAMJ1RIFBwDBAAAEAAMJ1RIFBwDBAAAuAAQKf3wAAwQACQmYH7QAAMMCAAQACQmYH7QAAMMCAAMAAgn2Apr6ABoAAAAA.',
Ni='Nickyboy:BAABLgAECn8qAAQeAAcJmyLhBQAKAgAeAAcJmyLhBQAKAgAhAAIJvg54BwFhAAAdAAEJrBd0PQA3AAAAAA==.Nightevel:BAAALgAECgUJBQAAAA==.Nihimetal:BAAALgAECgYJCQAAAA==.Nikash:BAABLgAECn80AAMGAAkJFBNVHADnAQAGAAkJFBNVHADnAQADAAYJ+QhgfwC8AAAAAA==.Nisato:BAAALgAECgUJBQAAAA==.',
No='Noctum:BAAALgAECgYJEAAAAA==.Nommei:BAAALgAECgcJEwAAAA==.Northic:BAAALgAECgYJBgABLgAECgkJNQAMAPEgAA==.Nortikolait:BAAALgAECgEJAQABLgAECgkJNQAMAPEgAA==.',
Ny='Nyriah:BAAALgAECgUJCwAAAA==.Nyxys:BAAALgAECgMJAwAAAA==.',
Ob='Obm:BAAALgAECgUJCwAAAA==.',
Oc='Octoface:BAAALgAECgYJBQAAAA==.Octt:BAACLgAFFH8HAAIhAAMJoRntagDuAAAhAAMJoRntagDuAAAuAAQKfyAAAiEACQk5HEgIAI8BACEACQk5HEgIAI8BAAAA.',
Of='Offal:BAABLgAECn82AAQjAAYJjxUrBgAaAQAXAAYJCAsJGAA5AQAjAAYJjxUrBgAaAQAlAAEJJQV2swAjAAAAAA==.',
Ol='Olanna:BAAALgAECgYJDAAAAA==.Oldcannabis:BAAALgAECgQJCwAAAA==.',
Om='Ominis:BAAALgAECgYJCgAAAA==.',
Oo='Oomaw:BAAALgAFFAEJAQAAAA==.',
Or='Orcal:BAACLgAFFH8hAAIkAAYJshT7KQAgAQAkAAYJshT7KQAgAQAuAAQKfx0AAiQACAn7GnQQAHECACQACAn7GnQQAHECAAAA.Ormie:BAAALgAECgQJBAAAAA==.Orney:BAAALgADCgcJBwAAAA==.Ornimus:BAABLgAECn8jAAQOAAgJDBFABwAEAQAOAAgJDBFABwAEAQANAAQJEARkKAGJAAARAAIJLgX7GwBGAAAAAA==.Ortian:BAAALgAECgEJAQABLgAECgUJCAALAAAAAA==.',
Ot='Otherrhu:BAAALgAECgYJCAAAAA==.',
Oz='Ozo:BAABLgAECn8dAAIFAAcJqBIgbQBnAQAFAAcJqBIgbQBnAQAAAA==.',
Pa='Paiva:BAAALgAECgYJCQAAAA==.Palandor:BAAALgADCgMJAwAAAA==.Pallyscorned:BAABLgAECn9FAAIOAAkJ/iHjAgD3AgAOAAkJ/iHjAgD3AgAAAA==.Pampas:BAABLgAECn8bAAMBAAkJkgSndAD/AAABAAkJkgSndAD/AAAVAAEJ5AFvwwAZAAAAAA==.Panduh:BAAALgAECgYJCQABLgAFFAQJEQAMAJ4gAA==.Paxdei:BAAALgAECgUJCQAAAA==.',
Pe='Ped:BAAALgAECgQJBgAAAA==.',
Ph='Phenixy:BAAALgAECgYJDAAAAA==.Phoebell:BAAALgAECgYJDQAAAA==.',
Pi='Pinkducky:BAABLgAECn8nAAIMAAcJ1gdmHgDJAAAMAAcJ1gdmHgDJAAAAAA==.',
Pl='Platinumsoul:BAAALgADCgIJAgAAAA==.Plen:BAACLgAFFH8FAAIMAAMJ9RC+pwDMAAAMAAMJ9RC+pwDMAAAuAAQKfzAAAxwACQnNH/QDAMMBAAwACQmnHFo1AGECABwABgk/IPQDAMMBAAAA.',
Po='Ponder:BAAALgAECgYJCgAAAA==.Poppyseed:BAAALgAECgQJBAAAAA==.Poquads:BAAALgAECgQJCgAAAA==.',
Pr='Priestdoof:BAAALgADCgcJBwAAAA==.Primaris:BAAALgAECgcJDAAAAA==.Prinnce:BAAALgAECgcJDgABLgAECgkJVQAJABokAA==.Príestatute:BAAALgAECgUJBQABLgAFFAMJCwAFAAAXAA==.',
Pu='Pulmifinger:BAAALgAECgEJAwAAAA==.Punka:BAAALgAECgEJAQAAAA==.Purplesea:BAAALgADCgcJDQABLgAECgkJOgARAGYTAA==.',
Pv='Pve:BAAALgAECgcJCAAAAA==.',
Py='Pygon:BAAALgAECgIJAgAAAA==.',
Qi='Qilt:BAAALgADCgcJBwAAAA==.',
Qu='Quasar:BAABLgAECn8lAAIiAAkJmBgVQQAZAgAiAAkJmBgVQQAZAgAAAA==.',
Ra='Raaluur:BAAALgAECgQJBwAAAA==.Radra:BAACLgAFFH8JAAMUAAQJVwUPEwCYAAAUAAQJ7gMPEwCYAAACAAMJ0ARaPwBzAAAuAAQKf1AABBQACQm7Fc8DANsBABQACQlAFc8DANsBABAABwnEDZUDACUBAAIABgn6DOwZALkAAAAA.Radras:BAAALgAECgcJCQAAAA==.Raeku:BAABLgAECn8tAAImAAkJkCAUBgDCAgAmAAkJkCAUBgDCAgAAAA==.Rainee:BAAALgADCgYJBwAAAA==.Raja:BAAALgAECgUJDwAAAA==.Rathalo:BAAALgAECgQJBgAAAA==.Rav:BAAALgADCgUJBQAAAA==.Ravick:BAAALgADCgEJAQAAAA==.Razensetral:BAAALgAECggJCAAAAA==.Razzlor:BAAALgADCgUJBQAAAA==.',
Re='Reducto:BAABLgAECn8hAAMQAAYJhRXmFwDiAAACAAYJnBNxfgAjAQAQAAUJPxXmFwDiAAAAAA==.Reenailinefh:BAAALgADCgcJDgAAAA==.Relitha:BAAALgADCgUJCQAAAA==.Remeii:BAABLgAECn8iAAMBAAgJJghPgADgAAABAAcJtgRPgADgAAAVAAYJUQP9cQCVAAAAAA==.Retribution:BAABLgAECn85AAINAAkJ5hM9SADtAQANAAkJ5hM9SADtAQAAAA==.Reylexgt:BAAALgAECgEJAQAAAA==.',
Rh='Rhaenera:BAAALgAECgMJCgABLgAECgkJVQAJABokAA==.Rhage:BAAALgADCgkJCQAAAA==.',
Ri='Richcraniums:BAAALgADCgcJBwAAAA==.Rivkah:BAAALgAECgEJAQAAAA==.',
Ro='Roachers:BAAALgADCgIJAgAAAA==.Robomurph:BAAALgADCggJDwAAAA==.Rolas:BAAALgAECgYJAgAAAA==.Ronfax:BAACLgAFFH8+AAMBAAgJQCO0AAAyAwABAAgJQCO0AAAyAwAVAAQJthXxFQDrAAAuAAQKfywAAwEACQm2IzwFAF8DAAEACQm2IzwFAF8DABUABgmeHN8qAJwBAAAA.Ronia:BAAALgADCgIJAgABLgAECggJGwACAMMYAA==.Rooss:BAAALgAECgcJEgAAAA==.Roqane:BAAALgAECgQJBAAAAA==.Roserade:BAABLgAECn8UAAMcAAkJQxSKHwBYAQAcAAkJ5xOKHwBYAQAbAAEJ+AyqPAAtAAAAAA==.Rothkin:BAAALgADCgMJAwAAAA==.Rotreiter:BAAALgADCgEJAQAAAA==.Rowdyredneck:BAAALgADCgMJAwABLgAECggJGQAJAGIXAA==.',
Ru='Rukea:BAABLgAECn8jAAMMAAkJwRwpSADqAQAMAAkJwRwpSADqAQAbAAEJyhBgFgA3AAAAAA==.Rul:BAAALgAFFAEJAQABLgAFFAQJEQAMAJ4gAA==.',
Ry='Ryllae:BAAALgAECgQJBQABLgAECgkJHgAUAFciAA==.Ryuusythe:BAAALgADCgcJBwAAAA==.Ryân:BAAALgADCgEJAQAAAA==.',
['Rì']='Rììdìì:BAACLgAFFH8GAAIdAAMJtgdGBwCzAAAdAAMJtgdGBwCzAAAuAAQKfxQAAh0ABwnxFJgCAIkBAB0ABwnxFJgCAIkBAAEuAAUUAwkLAAUAABcA.',
Sa='Saara:BAAALgADCgEJAQAAAA==.Sackhammer:BAAALgAECgQJBAAAAA==.Saint:BAAALgAECgkJDwAAAA==.Salopard:BAAALgAECgIJAgAAAA==.Samson:BAABLgAECn8ZAAQJAAgJ8xvRIgCaAQAJAAcJ6xvRIgCaAQAKAAUJtxHfTgDFAAAWAAIJ3wpgqgBJAAABLgAECgUJCwALAAAAAA==.Sanivan:BAABLgAECn8VAAIUAAcJ+hdxGgDvAQAUAAcJ+hdxGgDvAQAAAA==.Sanoan:BAAALgAECgQJBQAAAA==.Saori:BAAALgAECgEJAQAAAA==.Sappy:BAABLgAECn8aAAQgAAcJdR9BCQCuAQAgAAYJsh5BCQCuAQAIAAQJrxwzOwA/AQAnAAQJ8BLcCQDFAAABLgAFFAQJEQAMAJ4gAA==.Sarinae:BAABLgAECn8qAAQkAAkJeAddDQCgAAAkAAgJzwVdDQCgAAAfAAEJGQ47CgAsAAAYAAEJwAEQRAAfAAAAAA==.Sarmuc:BAABLgAECn8dAAMZAAkJtxZlAwB/AQAZAAkJtxZlAwB/AQAVAAEJXwuesAAoAAAAAA==.Sarnluz:BAAALgAECgEJAQABLgAECggJEQALAAAAAA==.Saryda:BAAALgAECgYJDgABLgAECgcJCAALAAAAAA==.Sauda:BAAALgAECgMJBAAAAA==.Saurian:BAAALgADCgEJAQAAAA==.',
Sc='Schadoww:BAAALgAECggJDQABLgAFFAMJBQAMAPUQAA==.Scubagal:BAAALgAECgYJDQAAAA==.Scy:BAAALgAECggJDgAAAA==.Scythraza:BAABLgAECn8/AAMkAAgJTBtsAgDdAQAkAAgJTBtsAgDdAQAYAAIJTw7oDABHAAAAAA==.',
Se='Seablue:BAAALgAECgMJBQABLgAECgkJOgARAGYTAA==.Sedaleice:BAAALgAECgEJAQAAAA==.Sedge:BAAALgADCgEJAQAAAA==.Seedsprayer:BAAALgAECgYJDAAAAA==.Selara:BAAALgAECgMJAwAAAA==.Sellenah:BAABLgAECn8bAAICAAgJwxjOXAByAQACAAgJwxjOXAByAQAAAA==.Sensu:BAABLgAECn8UAAMHAAcJIA1QEwCuAAAHAAcJIA1QEwCuAAAPAAEJHwOXmAAgAAAAAA==.Sensual:BAAALgAECgYJAwAAAA==.Sernian:BAABLgAFFH8IAAIFAAQJWBS+JQAPAQAFAAQJWBS+JQAPAQABLgAFFAUJHwANAPgjAA==.Seä:BAABLgAECn86AAIRAAkJZhMXHAAjAgARAAkJZhMXHAAjAgAAAA==.',
Sh='Shadoweave:BAABLgAECn8dAAIPAAkJqwfcMwBJAQAPAAkJqwfcMwBJAQAAAA==.Shampooshady:BAAALgAECgMJBAAAAA==.Shandrin:BAAALgAECgIJAgAAAA==.Shapadin:BAAALgADCgcJBwABLgAECgkJGgAGAH0WAA==.Shapzan:BAABLgAECn8aAAMGAAgJfRYhLwBjAQAGAAgJfRYhLwBjAQAaAAUJ3g2cDgCcAAAAAA==.Shareliss:BAAALgADCgYJBgAAAA==.Sharks:BAAALgAECgQJDwAAAA==.Shiik:BAAALgAECgYJBwAAAA==.Shivant:BAACLgAFFH8HAAIBAAMJYA8mKwCeAAABAAMJYA8mKwCeAAAuAAQKfzoAAwEACQlJHa0VAJ0CAAEACQlJHa0VAJ0CABUAAglDBZ6bAEEAAAAA.Shmeegleroop:BAAALgAECgYJDgAAAA==.Shroomhunter:BAAALgAECgEJAQAAAA==.Shîvå:BAACLgAFFH8IAAIQAAMJ6SGLAwACAQAQAAMJ6SGLAwACAQAuAAQKfzEAAhAACQniID0CAOQCABAACQniID0CAOQCAAAA.',
Si='Sideburns:BAAALgAECgMJAwAAAA==.Silvertime:BAAALgADCgYJBwAAAA==.Sindice:BAAALgAECgYJCwABLgAFFAgJPgABAEAjAA==.',
Sk='Skaa:BAAALgAECgEJAwAAAA==.',
Sl='Slammy:BAAALgAECgQJBAAAAA==.Slanesh:BAAALgAECgIJAgAAAA==.Slimpooshady:BAACLgAFFH8MAAIaAAMJvQw6FgB3AAAaAAMJvQw6FgB3AAAuAAQKfzQAAwMACQkWEn0oAA4CAAMACQkWEn0oAA4CABoACQmmEzcRANgBAAAA.Sloth:BAABLgAECn87AAIcAAkJICFSAQDGAgAcAAkJICFSAQDGAgAAAA==.',
So='Solaspirus:BAABLgAECn8uAAMCAAkJ6BsEJAA/AgACAAkJ6BsEJAA/AgAQAAEJawxCNwAqAAAAAA==.Solinius:BAAALgAECgQJBQAAAA==.Sope:BAAALgAECgYJDQABLgAECggJDgALAAAAAA==.Sorhtx:BAAALgAECgUJBwAAAA==.Sostoned:BAAALgAECgEJAQABLgAECgkJNAAgAPEcAA==.Soulomatic:BAAALgADCgcJBwAAAA==.',
Sp='Spectors:BAACLgAFFH8HAAIdAAMJjQWDBwCvAAAdAAMJjQWDBwCvAAAuAAQKf0gAAx0ACAmMEugDAD0BAB0ABwkcFegDAD0BACEABwnnA3DBAMoAAAAA.Spekturx:BAAALgAECgEJAQAAAA==.Spideygirl:BAABLgAECn8WAAIRAAgJPxzPEQCFAgARAAgJPxzPEQCFAgAAAA==.Sprayinnseed:BAAALgAECgMJBAAAAA==.Sprayinseed:BAAALgADCgMJAwAAAA==.',
Sq='Squarepants:BAAALgAECgQJCQABLgAECgQJDwALAAAAAA==.',
St='Stabon:BAABLgAECn8lAAIIAAkJcwlDHwCcAQAIAAkJcwlDHwCcAQAAAA==.Stalaediir:BAAALgADCgQJBAAAAA==.Stardre:BAAALgADCgQJBQAAAA==.Stevesmith:BAAALgAECgEJAgAAAA==.Stonedrage:BAAALgADCgEJAQAAAA==.Stormspirits:BAAALgADCgUJBQAAAA==.Sturdyy:BAAALgADCgMJAwAAAA==.Stãrkïllér:BAAALgADCgMJAwAAAA==.',
Su='Sugarmarks:BAAALgAECgYJDwAAAA==.',
Sw='Sweetstorm:BAABLgAECn94AAIUAAkJFg8JBgByAQAUAAkJFg8JBgByAQAAAA==.',
Sy='Synvara:BAAALgADCgUJBQAAAA==.',
['Sê']='Sêphiroth:BAABLgAECn83AAIRAAkJWxeEFABqAgARAAkJWxeEFABqAgAAAA==.',
Ta='Taekoad:BAAALgADCgIJAgAAAA==.Tahlia:BAAALgAECgEJAQAAAA==.Tania:BAABLgAECn8aAAINAAgJsxMTXwCzAQANAAgJsxMTXwCzAQAAAA==.Taredelaria:BAAALgAECgEJBAAAAA==.Tarixx:BAABLgAFFH8GAAMNAAMJ/w5hJACjAAANAAIJQg5hJACjAAAOAAEJeRA0GgAqAAAAAA==.Tazanoth:BAACLgAFFH8IAAQFAAMJBBLAcQC8AAAFAAMJ0Q/AcQC8AAAmAAIJKQ7lKwCDAAASAAEJTArEJgBPAAAuAAQKfyEAAyYACQmaG4kPADYCACYACQmQGokPADYCABIABglBGtYwALABAAAA.',
Te='Teasa:BAACLgAFFH8PAAIFAAMJHw39NQDRAAAFAAMJHw39NQDRAAAuAAQKf0IAAgUACQnZGYohAF8CAAUACQnZGYohAF8CAAAA.Teasham:BAACLgAFFH8NAAIVAAMJEwwDIACkAAAVAAMJEwwDIACkAAAuAAQKfzYAAhUACQkmFPgGAHoBABUACQkmFPgGAHoBAAAA.Tekeela:BAAALgAECgYJCgABLgAFFAcJFAAFAN8VAA==.Tekeelà:BAACLgAFFH8UAAQFAAcJ3xVDAgB7AQAFAAcJ3xVDAgB7AQASAAEJVgAiLgA1AAAmAAIJXwEtIAAYAAAuAAQKfzMABAUACQmJIaMVAIoCAAUACQkHH6MVAIoCACYACQn8Gp8PADUCABIABwm3EeY5AHoBAAAA.Tekkamaki:BAAALgADCgcJCAAAAA==.',
Th='Thalion:BAABLgAECn8gAAMFAAYJ0ATINAB7AAAFAAYJ0ATINAB7AAAmAAUJcgF+VQBXAAAAAA==.Theenna:BAABLgAECn8XAAMhAAgJ3AkcFwC9AAAhAAcJYgccFwC9AAAeAAQJuQuzCQCeAAAAAA==.Thetodd:BAAALgAECgIJAgAAAA==.Thianna:BAABLgAECn8pAAMRAAkJyBn5GwAkAgARAAkJyBn5GwAkAgANAAgJdRKeHwDmAAAAAA==.Thiculuskage:BAABLgAECn8YAAIRAAkJvB77BwAMAwARAAkJvB77BwAMAwAAAA==.Thinkso:BAAALgADCgcJGwAAAA==.Thobu:BAAALgAECgcJCwAAAA==.Thodos:BAAALgADCgEJAQAAAA==.Thornscale:BAABLgAECn9OAAQkAAkJ3ho3EQBcAgAkAAkJ3ho3EQBcAgAYAAYJogvrKAAsAQAfAAYJbhZhAgAmAQAAAA==.Thorrent:BAAALgADCgcJDQAAAA==.',
Ti='Tigolcrittys:BAAALgAECgcJEgABLgAFFAMJCwAFAAAXAA==.Timeforloads:BAABLgAECn8rAAMDAAkJFx+uMgDUAQADAAYJxB+uMgDUAQAGAAcJOhUdNABIAQAAAA==.Tirria:BAAALgAECgYJCQAAAA==.',
To='Tolk:BAAALgAECgcJEQAAAA==.Tomzombe:BAAALgAECgQJBgAAAA==.Totem:BAABLgAECn8WAAIVAAgJvQu3RQAdAQAVAAgJvQu3RQAdAQAAAA==.Totenz:BAAALgADCgYJBgAAAA==.Tovê:BAAALgAECgkJCQAAAA==.',
Tr='Traveler:BAAALgAECgIJAgAAAA==.Trickyflamom:BAABLgAECn8aAAIiAAcJzBwNCwCzAQAiAAcJzBwNCwCzAQABLgAFFAQJIgAiAPYaAA==.Troloq:BAABLgAECn85AAQdAAkJfx2BCADgAQAhAAgJHhuKNwD7AQAdAAgJWReBCADgAQAeAAYJTRoEFAAQAQAAAA==.Trondoom:BAAALgADCgYJBgAAAA==.',
Tu='Tugboattimmy:BAAALgAECgEJAQAAAA==.Tulisha:BAAALgAECgUJCgAAAA==.Turero:BAABLgAECn8WAAIRAAcJkAeuCwD+AAARAAcJkAeuCwD+AAABLgAFFAQJGAADAEIRAA==.Turger:BAAALgAECgUJCAABLgAECgkJEAALAAAAAA==.Turinnii:BAAALgADCgcJBwAAAA==.',
Ul='Uller:BAABLgAECn8oAAIiAAkJDhrQMABWAgAiAAkJDhrQMABWAgAAAA==.',
Um='Umbrafang:BAAALgAECgEJBAAAAA==.',
Un='Unholyspirit:BAAALgAECgQJDwAAAA==.',
Va='Vahlorraa:BAABLgAECn8oAAMRAAgJGw8xCABSAQARAAcJMhAxCABSAQANAAEJdAMQegATAAAAAA==.Vaimei:BAACLgAFFH8GAAIhAAMJQBUPNgCxAAAhAAMJQBUPNgCxAAAuAAQKfz0AAx4ACQlBIy8CAKICAB4ACAk9Iy8CAKICACEACAlhID8WAJ8CAAAA.Valashune:BAAALgADCgEJAQAAAA==.Valsilla:BAAALgAECgYJBgABLgAECgkJHgAUAFciAA==.Vapor:BAABLgAECn80AAIgAAkJ8RyeAABaAgAgAAkJ8RyeAABaAgAAAA==.Varaine:BAAALgAECgMJAwAAAA==.Varanius:BAAALgAECgEJAgAAAA==.',
Ve='Veebes:BAAALgAECggJCAAAAA==.Veebs:BAABLgAECn8tAAQlAAkJFRsZAwAeAgAlAAgJSBoZAwAeAgAXAAIJuB4oCwC2AAAjAAEJAAAySAAuAAAAAA==.Velóran:BAAALgADCgcJBwAAAA==.Vendola:BAABLgAECn8gAAIiAAgJaQboqgAqAQAiAAgJaQboqgAqAQAAAA==.Vento:BAABLgAECn8VAAIMAAgJjxWuYgCjAQAMAAgJjxWuYgCjAQAAAA==.Verité:BAABLgAECn8UAAMfAAgJ8gwzDwAXAQAfAAcJdg4zDwAXAQAkAAcJfQmBTgD0AAAAAA==.Veterpeinss:BAAALgADCggJDgAAAA==.',
Vi='Viento:BAAALgADCgcJBwAAAA==.Villiveil:BAAALgAECgEJAQABLgAFFAQJBgANAJoZAA==.Vintersorg:BAAALgAECgUJCQAAAA==.Virauca:BAABLgAECn9OAAICAAkJjhYtLgAOAgACAAkJjhYtLgAOAgAAAA==.Viuhl:BAAALgADCgQJAwAAAA==.',
Vo='Vodgrax:BAAALgAECgIJAgAAAA==.Voidstar:BAAALgAECgUJDAAAAA==.Voltimand:BAAALgAECgEJAQABLgAFFAMJCgABAGcPAA==.',
Vv='Vvicked:BAABLgAECn8gAAIMAAgJrCI8FwC7AgAMAAgJrCI8FwC7AgAAAA==.',
Vy='Vynesta:BAABLgAECn8eAAIUAAkJVyKvAwAZAwAUAAkJVyKvAwAZAwAAAA==.',
Wa='Wala:BAAALgAECgcJDAAAAA==.Wamoo:BAAALgAECgEJAgAAAA==.Wanagi:BAAALgAECgUJBwAAAA==.Wankz:BAAALgAECgkJEgAAAA==.Wankzerkin:BAAALgADCgEJAQAAAA==.Warriorguyes:BAABLgAECn8fAAIlAAkJtSKbBwDlAgAlAAkJtSKbBwDlAgAAAA==.',
We='Weyna:BAABLgAECn84AAMWAAgJ3hHVMgCsAQAWAAgJ3hHVMgCsAQAKAAYJVAmnTQDJAAABLgAFFAYJHwAYAO8UAA==.',
Wh='Whisperingei:BAAALgAECgYJCgAAAA==.Whomper:BAABLgAECn8dAAMaAAcJgRJ+CQDyAAAaAAUJkxV+CQDyAAAEAAcJZQnHCAC3AAAAAA==.Whpheonix:BAAALgADCgkJEAAAAA==.',
Wi='Wickedshadow:BAAALgAECgMJAwAAAA==.Widowx:BAACLgAFFH8JAAMVAAMJaw/AIACgAAAVAAMJaw/AIACgAAABAAEJEgEjjwAgAAAuAAQKfzUAAhUACQlGHS8EAO0BABUACQlGHS8EAO0BAAAA.Winfurdal:BAAALgADCggJCAAAAA==.',
Wo='Womphunt:BAABLgAECn8WAAIFAAcJlBqgPgDnAQAFAAcJlBqgPgDnAQABLgAECgkJLAATABkhAA==.',
Wr='Wrandohunt:BAAALgAECgEJBAAAAA==.Wrandowdemon:BAAALgADCgcJBwAAAA==.Wreckitrandy:BAAALgAECgEJAQAAAA==.Wryn:BAAALgAECgkJEQABLgAFFAMJBQAMAPUQAA==.',
Wu='Wulyn:BAAALgAECggJEAAAAA==.',
Wy='Wylla:BAABLgAECn8YAAIJAAcJvQ/JBgAuAQAJAAcJvQ/JBgAuAQAAAA==.',
Xa='Xalethra:BAABLgAECn89AAICAAkJ8CQ7BQA0AwACAAkJ8CQ7BQA0AwAAAA==.Xaltheris:BAAALgAECgUJBgAAAA==.',
Xe='Xelha:BAAALgAECgYJBgAAAA==.Xenophobias:BAABLgAECn8aAAMcAAcJyBFUCAAEAQAcAAcJyBFUCAAEAQAMAAIJUgMdowEdAAAAAA==.',
Xh='Xhosen:BAABLgAFFH8HAAIMAAIJEhKdbgB8AAAMAAIJEhKdbgB8AAAAAA==.',
Xr='Xratedmurdaa:BAAALgAECgEJAQAAAA==.',
Xs='Xsuns:BAABLgAECn9JAAIDAAkJYxqqHQBZAgADAAkJYxqqHQBZAgAAAA==.',
Ya='Yarloon:BAAALgADCgcJBwAAAA==.',
Yo='Yodapan:BAAALgADCgkJEgABLgAECgkJFwAGADcLAA==.',
Yt='Ytsirk:BAAALgADCgYJBgAAAA==.',
Yv='Yve:BAAALgAECgUJDQAAAA==.',
Za='Zaharian:BAAALgAECgEJAgAAAA==.Zalajin:BAAALgAECgUJCQAAAA==.Zalila:BAAALgADCgYJBgAAAA==.Zanasi:BAEALgAECggJDgABLgAFFAUJFAAFABQiAA==.Zarayndia:BAAALgAECgYJCAAAAA==.',
Ze='Zeddicus:BAABLgAECn8tAAMdAAkJ9wi2DgBwAQAdAAkJfAi2DgBwAQAhAAUJDgXk8gB8AAAAAA==.Zendragan:BAACLgAFFH8HAAIWAAMJzxAbQQCfAAAWAAMJzxAbQQCfAAAuAAQKfx4AAhYACQlOGOcXAFkCABYACQlOGOcXAFkCAAEuAAUUAwkKAAcAsxEA.Zerhas:BAAALgAECgEJAwAAAA==.',
Zo='Zoe:BAAALgAECgQJCQAAAA==.Zoidz:BAAALgAECggJDAAAAA==.Zombiemagic:BAAALgADCgMJAwAAAA==.Zombruh:BAAALgAECgEJAQAAAA==.Zomgimlothar:BAAALgADCgIJAwAAAA==.Zoomy:BAAALgAECgQJCwAAAA==.',
Zy='Zyntarum:BAAALgADCgEJAQAAAA==.Zythopoios:BAAALgAFFAEJAgAAAA==.',
Zz='Zzilladi:BAABLgAFFH8SAAMTAAYJ1RkTCQC8AQATAAYJ1RkTCQC8AQAPAAEJAACzRAAAAAAAAA==.Zzilladinzz:BAACLgAFFH8UAAINAAUJjSBuMQBOAQANAAUJjSBuMQBOAQAuAAQKfyIAAg0ACQkIIwsSAAIDAA0ACQkIIwsSAAIDAAAA.',
['Ëu']='Ëulogy:BAAALgAECgcJEQABLgAFFAMJCAAQAOkhAA==.',
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
