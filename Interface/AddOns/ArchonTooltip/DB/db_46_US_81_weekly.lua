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

local lookup = {'Shaman-Restoration','DemonHunter-Devourer','Druid-Restoration','Druid-Feral','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Priest-Discipline','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Priest-Shadow','DemonHunter-Vengeance','Paladin-Holy','Hunter-Marksmanship','Priest-Holy','DemonHunter-Havoc','Shaman-Elemental','Monk-Mistweaver','Warrior-Arms','Shaman-Enhancement','Druid-Guardian','DeathKnight-Blood','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','Rogue-Assassination','Warlock-Demonology','Mage-Frost','Warrior-Protection','Evoker-Augmentation','Warrior-Fury','Evoker-Preservation','Rogue-Subtlety','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aarmorr:BAABLgAECn9RAAIBAAkJmhk4FgCYAgABAAkJmhk4FgCYAgAAAA==.Aatus:BAAALgAECgMJBAAAAA==.',
Ab='Absoul:BAAALgAECgQJBAAAAA==.Abyssidia:BAAALgAECgIJAgAAAA==.',
Ac='Acinianis:BAAALgAECgEJAQAAAA==.Acinthos:BAAALgAECgQJBgAAAA==.',
Ad='Adiros:BAAALgADCgUJBQAAAA==.',
Ae='Aechelus:BAAALgADCgEJAQABLgAECggJFQACAAceAA==.Aedelas:BAAALgAECgIJBAAAAA==.Aeloriá:BAABLgAECn9LAAMDAAkJmCBxBwBAAwADAAkJmCBxBwBAAwAEAAEJFQGgOwAPAAAAAA==.Aelyra:BAAALgAECggJEgAAAA==.',
Ag='Agrosa:BAAALgAECgYJBgAAAA==.',
Ai='Aimeeiove:BAAALgAECgYJCgAAAA==.Airad:BAAALgADCgUJBgAAAA==.Airoldeel:BAAALgAECgEJAQAAAA==.',
Al='Alcarza:BAAALgAECgMJBQAAAA==.Alchon:BAABLgAECn8kAAIFAAkJ6xqGLwAeAgAFAAkJ6xqGLwAeAgAAAA==.Aldera:BAABLgAECn84AAIBAAkJwgmBCAArAQABAAkJwgmBCAArAQAAAA==.Aledish:BAAALgAECgEJAgAAAA==.Alicien:BAABLgAECn8jAAMGAAkJwRwpSADqAQAGAAkJwRwpSADqAQAHAAEJyhBgFgA3AAAAAA==.Alista:BAAALgAECgYJCwAAAA==.Alladon:BAAALgADCgUJBQAAAA==.Allykat:BAABLgAECn9MAAMDAAcJ1RjpAgC9AQADAAcJ1RjpAgC9AQAIAAYJRxEIPwATAQAAAA==.Alorris:BAAALgAECgQJBgABLgAECgkJGQAJAFggAA==.Alunathsong:BAAALgADCgcJBwAAAA==.Alvagíngras:BAAALgAECgkJEAAAAA==.Alyra:BAAALgAECgYJBgAAAA==.',
Am='Amaith:BAAALgAFFAIJAgAAAA==.Amantillado:BAAALgAECgQJBAABLgAECggJGQAKAGIXAA==.Amata:BAAALgAECgUJCwAAAA==.Amelianne:BAAALgAECgcJEQAAAA==.Amiria:BAAALgAECgYJBgAAAA==.Ammastary:BAAALgAECgQJBgAAAA==.Ammonfrey:BAAALgAECgEJAQAAAA==.Amorfati:BAAALgAECgEJAQAAAA==.',
An='Ananiel:BAAALgADCgQJBQABLgAECgkJLwALAA8bAA==.Andragos:BAAALgAECgQJBgAAAA==.Andrea:BAABLgAECn9JAAIEAAkJYR3oBACrAgAEAAkJYR3oBACrAgAAAA==.Andrelia:BAAALgADCgkJDwAAAA==.Anthria:BAAALgAECgcJEAAAAA==.',
Ao='Aoon:BAAALgAECgEJAQAAAA==.',
Ap='Apoleth:BAAALgADCgMJAwAAAA==.',
Aq='Aqules:BAAALgADCgEJAgAAAA==.',
Ar='Arcapeligo:BAAALgAECgEJAgAAAA==.Archonsfury:BAAALgAECggJDwAAAA==.Arilyn:BAAALgAECgMJAwAAAA==.Array:BAAALgAECgUJBQAAAA==.',
As='Asath:BAAALgAECgYJDAAAAA==.Ascended:BAAALgAECgEJAgABLgADCgkJCQAMAAAAAA==.Asheye:BAAALgAECgkJCgABLgAFFAMJBQAGAPUQAA==.Ashuranadi:BAAALgADCgcJBwAAAA==.Askir:BAAALgADCgMJAwAAAA==.Asnew:BAAALgAECgkJEQAAAA==.Asura:BAAALgAECggJDQAAAA==.Asyllaa:BAABLgAECn8eAAMNAAkJFx+LLABPAgANAAcJOyOLLABPAgAOAAYJ9hLNHwAWAQAAAA==.',
At='Atnawuerus:BAAALgAECgEJAQAAAA==.Atonement:BAABLgAECn8aAAMJAAkJJBqFFAA5AgAJAAgJNh2FFAA5AgAPAAQJLgkTcwBbAAABLgAFFAIJBQAQAKchAA==.Atullua:BAAALgADCgEJAQAAAA==.',
Au='Aumaril:BAABLgAECn8ZAAMRAAgJsBQrGwArAgARAAgJsBQrGwArAgANAAgJNxRyZACnAQAAAA==.Auralynn:BAABLgAECn8qAAINAAkJUAl/kgBOAQANAAkJUAl/kgBOAQAAAA==.',
Av='Avathar:BAAALgAECgMJBgAAAA==.Averus:BAABLgAECn9RAAIIAAkJ3hHJHQDaAQAIAAkJ3hHJHQDaAQAAAA==.',
Az='Azariel:BAABLgAECn8+AAINAAkJ5BM2DAAnAQANAAkJ5BM2DAAnAQAAAA==.Azenwraith:BAAALgADCgkJCQAAAA==.Azuriah:BAABLgAECn9LAAMOAAkJ6B3/BQCLAgAOAAkJIB3/BQCLAgANAAEJXyHCTgFfAAAAAA==.',
Ba='Baane:BAAALgAECgQJBwABLgAECgcJEQAMAAAAAA==.Babnik:BAEBLgAECn8YAAMFAAkJZBPBCgBIAQAFAAkJZBPBCgBIAQASAAIJPw0IMABYAAAAAA==.Bagel:BAACLgAFFH8eAAMRAAUJHCNeDQDhAQARAAUJHCNeDQDhAQANAAQJaQcvKAC3AAAuAAQKfxkAAxEACAmCH1AmAPYBABEACAmCH1AmAPYBAA0AAQnkCrKpASsAAAAA.Baldwin:BAAALgADCgcJBwAAAA==.Ballbreaker:BAAALgAECgQJBAAAAA==.Baminenherb:BAAALgADCgUJBQAAAA==.Bazluz:BAAALgADCgIJAwAAAA==.',
Be='Bearlysoberr:BAAALgAECgUJBQAAAA==.Bedhead:BAABLgAECn9CAAQJAAkJpRdwEQBdAgAJAAkJ7BZwEQBdAgATAAMJFBx6VQDgAAAPAAEJKwrXjgAsAAAAAA==.Bedrocked:BAAALgAECgIJAwAAAA==.Belaim:BAAALgAECgIJAgAAAA==.Belovis:BAACLgAFFH8fAAINAAYJiCRiCgByAQANAAYJiCRiCgByAQAuAAQKfyYAAg0ACQk0JOgMACYDAA0ACQk0JOgMACYDAAAA.Berathor:BAAALgAECgkJEwAAAA==.Betsea:BAAALgAECgUJBQABLgAECgkJOgARAGYTAA==.',
Bi='Bidoof:BAABLgAECn8vAAIUAAkJrA0rIAB4AQAUAAkJrA0rIAB4AQAAAA==.Bigblunt:BAAALgADCgcJEgAAAA==.Bigjohnii:BAAALgADCgcJBwAAAA==.Birdi:BAAALgAECgEJAQAAAA==.Bitemarks:BAAALgADCgcJDgAAAA==.',
Bl='Blackcoat:BAAALgAECgYJDwAAAA==.',
Bo='Boggrog:BAAALgAECgQJBAABLgAECgUJCwAMAAAAAA==.Bolz:BAAALgAECgMJAwAAAA==.Boosch:BAAALgADCgIJAgAAAA==.Bosshog:BAABLgAECn80AAIVAAkJpAvuNgBeAQAVAAkJpAvuNgBeAQAAAA==.Bowgobrr:BAABLgAECn8qAAMSAAgJ4xXlDgBvAQASAAgJ4xXlDgBvAQAFAAYJ2QpW3QCTAAABLgAFFAgJJgAFAEEQAA==.',
Br='Braelyne:BAABLgAECn8WAAINAAYJdR3JXwDEAQANAAYJdR3JXwDEAQAAAA==.Brasnite:BAAALgADCgEJAQAAAA==.Brewrock:BAAALgAECgQJCAAAAA==.Brewtilus:BAAALgADCgkJDgAAAA==.Brolaf:BAAALgAECgUJBQAAAA==.Broseidon:BAAALgAECgcJEQAAAA==.',
Bu='Buffsalot:BAAALgAECgUJDgAAAA==.Buffwarlock:BAAALgAECgcJBwAAAA==.Bullbatoo:BAAALgAECgEJAQAAAA==.Burlycheeks:BAABLgAECn85AAINAAkJPCCTGACwAgANAAkJPCCTGACwAgAAAA==.',
Ca='Caliista:BAAALgADCggJCAAAAA==.Carlitocool:BAAALgADCgIJAgAAAA==.Carraxus:BAAALgAECgQJDAAAAA==.Cassidyn:BAAALgADCgcJCAAAAA==.Castle:BAAALgAECgcJEgAAAA==.Catsneverdie:BAAALgAFFAEJAQABLgAFFAQJEQAGAKkMAA==.Catzinhatz:BAABLgAECn8YAAICAAcJAgq/jgADAQACAAcJAgq/jgADAQABLgAFFAQJEQAGAKkMAA==.',
Ce='Cecelya:BAABLgAECn9AAAQTAAkJ5RlLFwAUAgATAAkJ5RlLFwAUAgAPAAcJNhGCNABGAQAJAAMJUw1iXACOAAAAAA==.Celibate:BAAALgAECgUJBgAAAA==.Celothor:BAAALgADCgYJBgAAAA==.Celticmoon:BAAALgADCgQJBAAAAA==.',
Ch='Cherlia:BAABLgAECn8cAAIVAAYJIhMrDgBwAAAVAAYJIhMrDgBwAAABLgAECgkJHgAUAFciAA==.Chillykiller:BAAALgAECgYJBwABLgAECgkJHgAUAFciAA==.Chiva:BAAALgAECgQJBAABLgAECgkJOgABAEkdAA==.Chivactdl:BAAALgAECgMJBAABLgAECgkJOgABAEkdAA==.Chivalt:BAAALgAECgEJAQABLgAECgkJOgABAEkdAA==.Chonch:BAAALgAECgIJAgAAAA==.Chozen:BAAALgAECggJCwAAAA==.Chunknoriss:BAABLgAECn8vAAMWAAYJYiD3HQApAgAWAAYJYiD3HQApAgAKAAMJWwWbdwBhAAABLgAECgkJOgABAEkdAA==.',
Ci='Cigarettes:BAABLgAECn8XAAIXAAYJsRWnAwDxAAAXAAYJsRWnAwDxAAAAAA==.',
Cl='Claudiuss:BAAALgAECgYJDAABLgAFFAMJCgABAGcPAA==.Clurefu:BAABLgAECn84AAMWAAkJvCEQBQBaAwAWAAkJvCEQBQBaAwAKAAMJ5BZVWACuAAABLgAFFAIJCQADAFsZAA==.Clurelock:BAACLgAFFH8JAAIDAAIJWxmiFQCFAAADAAIJWhmiFQCFAAAuAAQKfzQAAgMACQktIi4EAHsDAAMACQktIi4EAHsDAAAA.Cluremage:BAAALgAECgYJEQAAAA==.Clurethyr:BAAALgAECggJEwAAAA==.',
Co='Cobblestone:BAAALgAECgIJAgAAAA==.Codenameknd:BAAALgAECgIJAgAAAA==.Comsuck:BAAALgAECgcJEQAAAA==.Conchobhar:BAABLgAECn8VAAIWAAkJlBoMGgBHAgAWAAkJlBoMGgBHAgAAAA==.Constella:BAAALgADCgYJCQAAAA==.Coppertan:BAAALgAECgMJBQAAAA==.Coralyne:BAAALgADCgEJAQAAAA==.Corrosion:BAABLgAECn8oAAIYAAkJLx2HBACnAgAYAAkJLx2HBACnAgAAAA==.',
Cr='Crazyshammy:BAAALgAECgkJEgAAAA==.Crommash:BAAALgAECgcJCgAAAA==.Crono:BAAALgAECgQJCQAAAA==.Crunchynuget:BAABLgAECn8pAAINAAkJbSDqAQCxAgANAAkJbSDqAQCxAgABLgAFFAUJGAANABkgAA==.',
Ct='Cthuwu:BAAALgAECgMJAgABLgAFFAYJEQAFAIsZAA==.',
Cu='Cujotaro:BAAALgAECgEJAgAAAA==.Cumberdale:BAAALgAECgUJBQAAAA==.',
Cv='Cvhamster:BAAALgAECgQJCgAAAA==.',
Cy='Cybeast:BAABLgAECn80AAMEAAkJRB54BAC4AgAEAAkJHh54BAC4AgAZAAUJFRgEAwBjAQAAAA==.Cynortas:BAAALgAECgIJBgAAAA==.',
Da='Daciana:BAABLgAECn8fAAIFAAgJqBEpEwDfAAAFAAgJqBEpEwDfAAAAAA==.Dados:BAABLgAECn8wAAMTAAkJXh5tDgCBAgATAAkJXh5tDgCBAgAPAAEJsBRKgAA9AAAAAA==.Daeghun:BAAALgAECgIJBQAAAA==.Dahleigh:BAAALgADCgkJDQAAAA==.Dakanar:BAAALgAECgQJBwAAAA==.Dambrien:BAAALgAECgUJBQAAAA==.Daravus:BAAALgAECgUJCAAAAA==.Darkfox:BAAALgAECgEJAQAAAA==.Darkhazel:BAAALgAECgEJAQAAAA==.Darkkromdor:BAABLgAECn8zAAINAAkJtR/SFwC0AgANAAkJtR/SFwC0AgAAAA==.Darloct:BAAALgAECgYJEQAAAA==.Dazzlor:BAAALgADCggJCAAAAA==.',
De='Deadelff:BAABLgAECn8kAAMCAAgJ2hZHYwBhAQAUAAYJexvxJwCDAQACAAgJQg9HYwBhAQAAAA==.Deadholypaly:BAAALgADCgEJAwAAAA==.Deadlifts:BAAALgAECgQJCQAAAA==.Deadlighted:BAAALgADCgcJDgABLgAECggJJAACANoWAA==.Deadslinger:BAAALgADCgYJDAAAAA==.Deadtotem:BAAALgADCgkJCQABLgAECggJJAACANoWAA==.Deammon:BAAALgAECgEJAQAAAA==.Deathcat:BAACLgAFFH8RAAIGAAQJqQy4NADOAAAGAAQJqQy4NADOAAAuAAQKfzsAAgYACQmjFgc4AB8CAAYACQmjFgc4AB8CAAAA.Deathkiss:BAAALgAECgYJEgAAAA==.Deathrat:BAAALgADCgUJBgAAAA==.Deathrixx:BAABLgAFFH8RAAQGAAUJZx4JVABKAQAGAAUJQh4JVABKAQAHAAIJhB3QHACdAAAaAAEJIBhWPABEAAAAAA==.Deathshadowx:BAAALgAECgUJCwAAAA==.Delryth:BAAALgAECgQJBAAAAA==.Demonkoh:BAAALgAECgUJCAAAAA==.',
Df='Dfault:BAAALgADCgEJAQAAAA==.',
Di='Discharged:BAAALgAECgQJBAABLgAECggJGQAKAGIXAA==.',
Dk='Dkdeathblade:BAAALgAECgEJAQAAAA==.Dkpheonix:BAABLgAECn80AAIPAAkJ6xXZAwBXAQAPAAkJ6xXZAwBXAQAAAA==.',
Do='Dolemite:BAABLgAECn8+AAMWAAcJHhYdLwC/AQAWAAcJHhYdLwC/AQAKAAcJpxPzBgC+AAAAAA==.Donalbain:BAACLgAFFH8KAAIBAAMJZw+8UwCqAAABAAMJZw+8UwCqAAAuAAQKfzAAAgEACQkCHpQBAIwCAAEACQkCHpQBAIwCAAAA.Dotdotgoose:BAAALgAECgQJCAAAAA==.',
Dr='Draconz:BAAALgAECgIJAgABLgAECgYJEAAMAAAAAA==.Draganpriest:BAABLgAFFH8IAAIJAAMJCA47GQB+AAAJAAMJCA47GQB+AAAAAA==.Draganussy:BAAALgADCgEJAQAAAA==.Draggo:BAAALgAECgEJAQAAAA==.Drakkira:BAAALgADCgYJBgAAAA==.Draxon:BAAALgAECgEJAQAAAA==.Dremar:BAABLgAECn8dAAMbAAgJ/Q6RGQDXAAAbAAYJRAyRGQDXAAAcAAcJMA0xBADDAAAAAA==.Druc:BAAALgAECgEJAgAAAA==.',
Du='Durock:BAAALgAECgMJBAAAAA==.',
Dy='Dynaris:BAAALgADCgMJAwAAAA==.',
Ei='Eianna:BAAALgAECgEJAQAAAA==.',
El='Elcachazo:BAAALgAECgIJAgAAAA==.Eldinn:BAAALgADCgcJBgAAAA==.Elenora:BAAALgAECgMJAwAAAA==.Elidor:BAAALgAECgYJDgAAAA==.Ellalangley:BAAALgAECgIJAgABLgAFFAMJBQAGAPUQAA==.Elthelas:BAAALgADCgEJAQAAAA==.Eluneatic:BAAALgADCggJCgAAAA==.Elyssaris:BAABLgAECn84AAIaAAkJ4xoyDgAnAgAaAAkJ4xoyDgAnAgAAAA==.Elzulkin:BAAALgADCgcJCgAAAA==.',
Em='Emmdeath:BAABLgAECn8XAAIGAAYJNgNWDgGaAAAGAAYJNgNWDgGaAAAAAA==.Emmils:BAABLgAECn8+AAIIAAkJfA1uKgCBAQAIAAkJfA1uKgCBAQAAAA==.Emìly:BAABLgAECn9UAAQKAAkJGiQiAwAyAwAKAAkJGiQiAwAyAwAWAAkJCxaKHwAeAgALAAUJRRUqRgDiAAAAAA==.',
En='Enderelvarg:BAABLgAFFH8FAAIdAAUJbw9TBQARAQAdAAUJbw9TBQARAQAAAA==.Endmicrobuys:BAAALgADCgUJBQAAAA==.Entaria:BAACLgAFFH8GAAINAAQJmhmFMQBOAQANAAQJmhmFMQBOAQAuAAQKf0EABA0ACQk7IYMOAPICAA0ACQk7IYMOAPICAA4ABwkxH24NAO4BABEABgm1DGJbAMgAAAAA.',
Eo='Eox:BAAALgADCgMJAwAAAA==.',
Ep='Episkey:BAABLgAECn8fAAMIAAkJERGOJgCZAQAIAAkJERGOJgCZAQADAAQJdRcgYQASAQAAAA==.',
Er='Erindaglaze:BAAALgADCgQJBQAAAA==.Erissae:BAAALgADCgEJAgAAAA==.Eropor:BAABLgAECn8iAAMWAAYJexPyQQBlAQAWAAYJexPyQQBlAQAKAAMJYQbMigBHAAABLgAFFAQJGAADAEIRAA==.Eroversion:BAACLgAFFH8YAAMDAAQJQhFrMwDgAAADAAQJQhFrMwDgAAAIAAEJtwEXJAAiAAAuAAQKf1YABQMACQlCHq8XAIkCAAMACQlCHq8XAIkCAAgABAkIFj5UANUAAAQAAwm4DUszAJEAABkAAQkAAFWVAAAAAAAA.',
Es='Esmay:BAABLgAECn8fAAIVAAkJHRRNIADhAQAVAAkJHRRNIADhAQAAAA==.Eso:BAAALgADCgYJCwAAAA==.',
Et='Ethren:BAABLgAECn9QAAIeAAkJ2RgJBABeAgAeAAkJ2RgJBABeAgAAAA==.',
Eu='Eudeyrn:BAAALgAECgYJAwAAAA==.',
Ev='Evilrepu:BAAALgAECgEJAQAAAA==.',
Ey='Eyebrows:BAAALgAECgIJAgAAAA==.',
Ez='Ezikarridge:BAAALgAECgEJAQAAAA==.',
Fa='Faker:BAAALgADCgEJAQAAAA==.Falcone:BAAALgAECgMJBgAAAA==.',
Fe='Felbolter:BAAALgAECgEJAwAAAA==.Feliri:BAAALgAECggJCgAAAA==.',
Fi='Filgulfin:BAABLgAECn9XAAMFAAkJTR+8EADLAgAFAAkJTR+8EADLAgASAAgJgRDREwAkAQAAAA==.Finkate:BAABLgAECn8XAAIFAAgJHA4FYwB/AQAFAAgJHA4FYwB/AQAAAA==.Firebad:BAABLgAECn8wAAMbAAkJpxy5AgCFAgAbAAkJpxy5AgCFAgAfAAYJHwrG5ACTAAAAAA==.Firebringer:BAABLgAECn9VAAICAAkJ9A7jSgCmAQACAAkJ9A7jSgCmAQAAAA==.Fistokaestey:BAAALgADCgkJEgABLgAECgkJIwAgANUXAA==.',
Fl='Flaakk:BAAALgADCgcJBwAAAA==.Flamehunter:BAABLgAECn8iAAMCAAkJMRqEHACnAgACAAkJcRmEHACnAgAUAAcJLRdgJACaAQAAAA==.Flo:BAABLgAECn9aAAMPAAkJhxwZCwCeAgAPAAkJhxwZCwCeAgATAAMJSAcyWAB5AAAAAA==.Floki:BAABLgAECn8UAAIhAAkJqhJnHQBKAQAhAAkJqhJnHQBKAQAAAA==.Flora:BAAALgAECgQJBAAAAA==.Flowing:BAABLgAECn8sAAIiAAkJyxmAAQDNAQAiAAkJyxmAAQDNAQAAAA==.',
Fo='Foods:BAACLgAFFH8VAAMjAAMJfhM8GACdAAAjAAMJfhM8GACdAAAhAAIJBgs/EABtAAAuAAQKf24ABCMACQlmHl8BAEsCACMACQlmHl8BAEsCACEACAlkFUkTALkBABcAAwnoDE0wAHUAAAAA.Foofsmash:BAAALgADCgUJBgAAAA==.',
Fr='Fripouille:BAAALgADCgMJAwAAAA==.',
Fu='Fustín:BAAALgAECgYJEgAAAA==.Fuzzyewok:BAAALgAECgYJEwAAAA==.',
['Fø']='Føøds:BAAALgADCgMJAwAAAA==.',
Ga='Gaboo:BAAALgAECgkJEwAAAA==.Garfman:BAAALgAFFAEJAQAAAA==.',
Gb='Gb:BAACLgAFFH8GAAIRAAUJGgzZHgAmAQARAAUJGgzZHgAmAQAuAAQKfxQAAhEABwknIYUSAH0CABEABwknIYUSAH0CAAEuAAUUBAkNAA8A8hoA.',
Gh='Ghostinhale:BAABLgAECn8XAAIGAAcJURXFbgCHAQAGAAcJURXFbgCHAQAAAA==.',
Gi='Gibbshole:BAAALgADCgcJBwAAAA==.Gilorion:BAABLgAECn8XAAIFAAkJ7RbnMgARAgAFAAkJ7RbnMgARAgAAAA==.',
Gl='Glasgoww:BAAALgAECgYJCQABLgAFFAMJCgABAGcPAA==.',
Gn='Gnibat:BAAALgAECgMJBgAAAA==.Gnomerlicous:BAAALgADCgkJCQAAAA==.',
Go='Goburina:BAACLgAFFH8RAAIBAAQJFAjcJACEAAABAAQJFAjcJACEAAAuAAQKfxgAAgEACQlaC1M9AIwBAAEACQlaC1M9AIwBAAAA.Golias:BAAALgADCgEJAQAAAA==.',
Gr='Grenache:BAAALgAECgcJCAAAAA==.Grievo:BAAALgAECgYJCQAAAA==.Grimdawn:BAAALgAFFAEJAQAAAA==.Grimtankdrud:BAAALgADCgcJBwAAAA==.Grinnir:BAAALgAECgEJAgABLgAECgYJGQACALwcAA==.',
Gu='Guildenstern:BAAALgADCgUJBQABLgAFFAMJCgABAGcPAA==.Gulpron:BAAALgAECgMJBAAAAA==.',
Gy='Gypsiey:BAAALgAECgUJBQAAAA==.',
['Gí']='Gímlí:BAACLgAFFH8KAAIFAAMJKBT7XADrAAAFAAMJKBT7XADrAAAuAAQKfzgAAgUACQm8HiQdAHYCAAUACQm8HiQdAHYCAAAA.',
Ha='Halcyndraag:BAABLgAECn9RAAQiAAkJLhUrIQDQAQAiAAcJKhUrIQDQAQAdAAMJwBcBGgCBAAAkAAEJPQJWRAAeAAAAAA==.Handbannana:BAAALgAECgQJBAAAAA==.Handsome:BAAALgAECgcJDAABLgAECgkJGQAPADQJAA==.Happydk:BAACLgAFFH8RAAMGAAQJniCPPgB6AQAGAAQJniCPPgB6AQAaAAMJKRHrLACVAAAuAAQKfygAAwYACQkdI2MXALoCAAYACQlaIWMXALoCABoABwlKGSMnABsBAAAA.Hartu:BAABLgAECn9JAAIhAAkJfxTyDwDpAQAhAAkJfxTyDwDpAQAAAA==.Harukasan:BAAALgADCgIJAgAAAA==.Hashpipe:BAAALgADCgMJAwAAAA==.Hazl:BAAALgAECgMJBAAAAA==.',
He='Healortank:BAAALgAECgEJAQAAAA==.Healsofpain:BAAALgADCgYJBgAAAA==.Healtardo:BAAALgAECgYJCAAAAA==.Hellankeller:BAAALgAECgQJBwAAAA==.Hemic:BAACLgAFFH8RAAIlAAMJMB+IDAD8AAAlAAMJMB+IDAD8AAAuAAQKfzMAAyUACQkjI18FAN0CACUACQkjI18FAN0CAB4ABAnwGhUQACMBAAAA.Hemmorage:BAAALgAECgYJCgABLgAFFAMJBQAGAPUQAA==.Herbalmist:BAAALgAECgUJCwAAAA==.',
Hi='Higag:BAAALgADCgQJBAAAAA==.Hippypally:BAAALgADCgEJAQAAAA==.Hircine:BAAALgAECgQJBAAAAA==.',
Ho='Holysea:BAAALgAECgYJDAABLgAECgkJOgARAGYTAA==.Horatio:BAAALgAECgEJAQABLgAFFAMJCgABAGcPAA==.',
Hr='Hraken:BAAALgAECgUJBgAAAA==.',
Hu='Hukruun:BAAALgADCgEJAgAAAA==.Huntrinei:BAAALgADCgYJBgAAAA==.',
['Hé']='Hélénkéller:BAAALgADCggJDwABLgAFFAMJBwAFABUYAA==.',
Ia='Iahawkeye:BAAALgADCgMJAwAAAA==.',
Ib='Ibhuntin:BAAALgAECggJEgAAAA==.',
Ic='Icyhooves:BAAALgAECgEJAQAAAA==.',
Id='Idiocracy:BAABLgAECn8lAAMhAAkJbhY/DQAWAgAhAAkJrRU/DQAWAgAjAAgJ2w7uMACJAQAAAA==.Idk:BAAALgADCgYJCgAAAA==.',
Ik='Ikodiwa:BAAALgADCgMJAwAAAA==.',
Il='Illigirl:BAAALgADCgEJAQAAAA==.',
Im='Imwithfloki:BAAALgAECgMJBgAAAA==.',
In='Indoti:BAAALgADCgUJBwAAAA==.',
Ir='Ironmark:BAAALgAECgUJCAAAAA==.Irys:BAAALgAECgMJAwAAAA==.',
Is='Isam:BAAALgADCgYJBgAAAA==.Isamidor:BAACLgAFFH8PAAIFAAUJYCIAKABnAQAFAAUJYCIAKABnAQAuAAQKfxwAAgUACQmXI+cEAD8DAAUACQmXI+cEAD8DAAAA.Ismokeu:BAACLgAFFH8TAAITAAQJbxeRBgAUAQATAAQJbxeRBgAUAQAuAAQKfzoAAhMACQmrGZ4NAIwCABMACQmrGZ4NAIwCAAAA.Ismyn:BAAALgAECgEJAQAAAA==.',
It='Itskemba:BAAALgADCgYJBgAAAA==.',
Iy='Iyania:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneal:BAABLgAECn8gAAINAAkJ+wQYpwAtAQANAAkJ+wQYpwAtAQAAAA==.Jalidelo:BAABLgAECn9JAAMJAAkJnh2cCADrAgAJAAkJnh2cCADrAgATAAEJ5gZihgAqAAAAAA==.Jaliwind:BAAALgADCgkJCQAAAA==.Jayan:BAAALgAECgEJAQAAAA==.',
Je='Jenifurr:BAAALgADCgIJAgAAAA==.Jenyx:BAAALgAECgQJBAAAAA==.',
Ji='Jimbowaboki:BAAALgADCgEJAQAAAA==.',
Jo='Johan:BAABLgAECn8eAAIfAAkJMhqFLAAnAgAfAAkJMhqFLAAnAgAAAA==.Jokers:BAABLgAECn8dAAMhAAYJKhR8IgAcAQAhAAYJFxN8IgAcAQAjAAUJ4g/8WQDoAAAAAA==.Jokersfists:BAABLgAECn8XAAICAAYJVg8wEAC4AAACAAYJVg8wEAC4AAAAAA==.Joranbragi:BAABLgAECn8tAAMNAAYJOQ6QFADLAAANAAYJhwuQFADLAAAOAAIJCQymCgBSAAAAAA==.Jordanjr:BAAALgAECggJEQAAAA==.Jormun:BAAALgADCgEJAQAAAA==.Joshy:BAABLgAECn8dAAIcAAYJsRCBDgBJAQAcAAYJsRCBDgBJAQAAAA==.Jotoonice:BAABLgAECn8aAAIgAAgJjBVjYQC9AQAgAAgJjBVjYQC9AQAAAA==.',
Jt='Jtoothaordan:BAACLgAFFH8TAAQmAAYJExf0FAAmAQAmAAQJ3xP0FAAmAQASAAMJsg0uLQBWAAAFAAIJAwgNqwBCAAAuAAQKfy4ABCYACAn9Hw8UAAUCABIACAn9F60gACACACYABgkaJA8UAAUCAAUAAglIIaDPAKsAAAAA.',
Ju='Juglfhednar:BAAALgADCgEJAQAAAA==.Jules:BAAALgAECgUJBQAAAA==.Justbob:BAAALgAECgUJBgAAAA==.',
['Jú']='Júgg:BAAALgAECgQJBgAAAA==.',
Ka='Kaachow:BAABLgAECn8uAAIDAAkJZR+DCQAiAwADAAkJZR+DCQAiAwAAAA==.Kaana:BAABLgAECn9PAAIFAAkJ7xmlHwBpAgAFAAkJ7xmlHwBpAgAAAA==.Kaestey:BAAALgAECggJDQABLgAECgkJIwAgANUXAA==.Kairis:BAAALgAECgYJCQAAAA==.Kallista:BAAALgADCgEJAQAAAA==.Kanoalandiwa:BAAALgAECgEJAQAAAA==.Karthagon:BAABLgAECn8kAAINAAYJeRitCQBPAQANAAYJeRitCQBPAQAAAA==.Karungash:BAACLgAFFH8LAAMfAAQJqgoMZAD/AAAfAAQJqgoMZAD/AAAbAAEJVQE+GwA+AAAuAAQKfx0AAx8ACAm1Id4QAPMCAB8ACAm1Id4QAPMCABsAAgkTEk1SAHcAAAAA.Karva:BAABLgAECn8kAAIQAAkJzBqWBgAqAgAQAAkJzBqWBgAqAgAAAA==.Karvy:BAABLgAECn8kAAIZAAgJXB4EAgCpAQAZAAgJXB4EAgCpAQABLgAECgkJJAAQAMwaAA==.Kash:BAAALgADCgUJBQABLgAFFAUJEwAEACYlAA==.Kayzer:BAAALgADCgYJGAAAAA==.',
Ke='Kelonaar:BAACLgAFFH8aAAIVAAUJASPQCQA3AQAVAAUJASPQCQA3AQAuAAQKfyUAAxUACQlhHqEWADECABUACQlhHqEWADECABgAAgn1Gg45AEoAAAAA.Kelya:BAAALgAECgUJBQABLgAFFAUJGgAVAAEjAA==.Kerrie:BAAALgADCgEJAQAAAA==.',
Kh='Khthonious:BAABLgAECn8VAAICAAcJBx4TOwDbAQACAAcJBx4TOwDbAQAAAA==.',
Ki='Kibblsncrits:BAAALgAECgIJAwABLgAECgkJEgAMAAAAAA==.Kickingdonut:BAACLgAFFH8FAAIKAAMJNx8sHADtAAAKAAMJNx8sHADtAAAuAAQKfywAAwoACAk7IxkJAOcCAAoACAk7IxkJAOcCAAsABgn1GUI3AG4BAAAA.Killerhottie:BAAALgAECgEJAQAAAA==.Killermoomoo:BAAALgAECgQJCgAAAA==.Kinoh:BAAALgADCgkJEAAAAA==.Kittykarma:BAAALgAECgUJBQAAAA==.',
Kl='Kloverr:BAAALgAECgIJAgAAAA==.Klub:BAAALgADCgYJBgAAAA==.',
Ko='Kollita:BAAALgAECgEJAQAAAA==.Komatsu:BAAALgAECgEJAQAAAA==.Kombatkarl:BAAALgADCgMJAwAAAA==.Koramere:BAAALgADCgcJBwAAAA==.',
Kr='Kretaios:BAAALgADCgQJBAAAAA==.Kromir:BAAALgAECgQJBAAAAA==.Kromnar:BAAALgADCgEJAQAAAA==.Kronixrage:BAAALgAECgYJCwAAAA==.Kronn:BAAALgAECgYJBwAAAA==.Krooler:BAAALgAECgQJCAAAAA==.Krum:BAACLgAFFH8gAAINAAUJaR8DKQBnAQANAAUJaR8DKQBnAQAuAAQKfx4AAg0ACAmsHYRRANQBAA0ACAmsHYRRANQBAAAA.',
Ku='Kungfoumoo:BAAALgAECgEJAQAAAA==.',
La='Ladgarkk:BAAALgADCggJFQAAAA==.Lanval:BAABLgAECn9aAAINAAkJgBtIIgB9AgANAAkJgBtIIgB9AgAAAA==.Lardend:BAABLgAECn8WAAIUAAgJ2QeGBgDVAAAUAAgJ2QeGBgDVAAAAAA==.Laurian:BAAALgADCgcJDwAAAA==.Laurì:BAAALgAECgMJBQABLgAECgkJVAAKABokAA==.',
Le='Leaky:BAAALgAECgIJBAAAAA==.Leetah:BAACLgAFFH8TAAIZAAMJ+R7CBQALAQAZAAMJ+R7CBQALAQAuAAQKf3YAAxkACQlkIpAAAMQCABkACQlkIpAAAMQCAAQAAwl9DmszAJEAAAAA.Leftblank:BAAALgAECgcJDQAAAA==.Legitimas:BAAALgAECgEJAQAAAA==.Lemix:BAAALgAECgMJDAAAAA==.',
Li='Liasong:BAAALgADCgMJAwAAAA==.Lilyoptra:BAAALgAECgYJDgABLgAECgYJDgAMAAAAAA==.Lindrael:BAAALgADCgEJAQAAAA==.Liszt:BAAALgAECgYJBgAAAA==.Litallya:BAAALgAECggJDQAAAA==.Littletush:BAAALgAECggJCAAAAA==.Livingdemon:BAAALgAECgUJDwAAAA==.',
Lm='Lminus:BAAALgAECgYJEgAAAA==.',
Lo='Lockolus:BAAALgAECgMJAwAAAA==.Lockpockets:BAAALgADCgEJAQAAAA==.Lootie:BAAALgAECggJDgAAAA==.Loriane:BAAALgAECgUJCAABLgAECgkJKAADAAIgAA==.Lorianth:BAAALgADCgcJDgAAAA==.Lotharbacco:BAAALgAECgMJAwAAAA==.Lovegood:BAAALgADCgEJAQAAAA==.Loveisbeauty:BAAALgAECgUJBwAAAA==.Lowki:BAAALgAECgEJAgAAAA==.',
Ly='Lychi:BAAALgAECgUJCwAAAA==.Lylora:BAACLgAFFH8cAAIDAAQJMCQZBgCmAQADAAQJMCQZBgCmAQAuAAQKf08AAgMACQm8JOIBALoDAAMACQm8JOIBALoDAAAA.Lysera:BAAALgADCgMJAwAAAA==.',
['Lê']='Lêmonaide:BAABLgAECn8sAAMTAAkJTQ+oJgCQAQATAAkJTQ+oJgCQAQAPAAUJAgXEagBzAAAAAA==.',
Ma='Madesh:BAABLgAECn9HAAMQAAkJSBv+BQA8AgAQAAkJtxj+BQA8AgACAAkJSRozKAAqAgAAAA==.Madman:BAABLgAECn8vAAIWAAkJTA9jOQCMAQAWAAkJTA9jOQCMAQAAAA==.Maelle:BAABLgAECn9RAAINAAkJ2iJZDAACAwANAAkJ2iJZDAACAwAAAA==.Magekaestey:BAABLgAECn8jAAIgAAkJ1RfHPAAnAgAgAAkJ1RfHPAAnAgAAAA==.Majandra:BAAALgAECgUJDAAAAA==.Malyndra:BAABLgAECn8yAAMUAAkJaBwEDwA1AgAUAAkJvxoEDwA1AgAQAAYJ9hksDgBvAQAAAA==.Malyssa:BAAALgADCgIJAgAAAA==.Marianne:BAAALgADCgYJBwAAAA==.Marle:BAAALgAECgEJBAAAAA==.Marvolt:BAABLgAECn8YAAIfAAgJcA0RbQBiAQAfAAgJcA0RbQBiAQAAAA==.Masy:BAAALgAECgEJAQAAAA==.',
Mc='Mcrae:BAAALgAECgYJBwAAAA==.',
Md='Md:BAAALgAECgEJAgAAAA==.',
Me='Medrare:BAAALgAECgEJAQAAAA==.Melon:BAAALgADCgEJAQABLgAECgkJDQAMAAAAAA==.Meriam:BAAALgAECgEJAgABLgAFFAMJBQAGAPUQAA==.Merlot:BAAALgADCgEJAgABLgAECgcJCAAMAAAAAA==.Mesmash:BAABLgAECn8wAAIhAAkJniFHBADjAgAhAAkJniFHBADjAgAAAA==.Metadk:BAAALgAECgQJBgABLgAECggJGQAKAGIXAA==.Metahunt:BAAALgAECgIJAgABLgAECggJGQAKAGIXAA==.Metamasters:BAAALgAECgQJBQABLgAECggJGQAKAGIXAA==.Metatotem:BAAALgAECgIJBAABLgAECggJGQAKAGIXAA==.Metavoker:BAAALgAECgEJAQABLgAECggJGQAKAGIXAA==.',
Mi='Mialtaa:BAABLgAECn8vAAILAAkJDxvjCwB2AgALAAkJDxvjCwB2AgAAAA==.Midgiit:BAAALgAECgUJBQABLgAFFAMJBQAGAPUQAA==.Miink:BAAALgADCgYJBgAAAA==.Milkurs:BAAALgAECgQJBwAAAA==.Miniborg:BAABLgAECn8iAAIFAAkJ+xo5HAB7AgAFAAkJ+xo5HAB7AgABLgAFFAUJGAANABkgAA==.Minidude:BAAALgAECgYJEAAAAA==.Minionghost:BAAALgADCggJCAAAAA==.Miyuki:BAAALgAECgQJBgAAAA==.',
Mj='Mjolnir:BAAALgAECgcJBgAAAA==.',
Mo='Moejojojo:BAABLgAECn8WAAIKAAkJ0yF4DwBTAgAKAAkJ0yF4DwBTAgAAAA==.Monkter:BAABLgAECn8ZAAQKAAgJYheyHADJAQAKAAgJYheyHADJAQAWAAEJ/gbfbgAmAAALAAEJfggUoAAiAAAAAA==.Monsignore:BAAALgADCgQJBAAAAA==.Moofasaha:BAAALgAECgkJEAAAAA==.Mooheals:BAAALgADCgEJAQAAAA==.Moonk:BAAALgAECgcJBQAAAA==.Morduos:BAAALgAECgcJBgABLgAECggJFQACAAceAA==.Morog:BAACLgAFFH8WAAMmAAYJURpxBQC4AQAmAAYJURpxBQC4AQAFAAEJ0w1tqwBCAAAuAAQKfykABBIACQmpGyMsAM0BABIABgmOHSMsAM0BAAUABgkbGq0/ALABACYABgnqE/UpAFEBAAAA.Morragan:BAAALgAECgQJBQAAAA==.Mortegom:BAAALgADCgcJBwAAAA==.Moráthi:BAAALgADCgcJBwAAAA==.',
Mu='Mulvan:BAAALgAECggJEQAAAA==.',
My='Myinja:BAAALgAECgQJCAABLgAECggJGQAKAGIXAA==.Myrddinwyllt:BAAALgAECgYJDAAAAA==.',
Na='Naadra:BAAALgAECgEJAQAAAA==.Nabû:BAAALgADCggJDwAAAA==.Naema:BAAALgAECggJDgAAAA==.Nalid:BAACLgAFFH8TAAIEAAUJJiW2AgCqAQAEAAUJJiW2AgCqAQAuAAQKf0QAAwQACQnAJkAAAIwDAAQACQnAJkAAAIwDAAgAAQmuAl6mABsAAAAA.Nanarus:BAACLgAFFH8NAAITAAIJfRnaEABgAAATAAIJfRnaEABgAAAuAAQKf1EAAxMACQmoHl8BADgCABMACQmoHl8BADgCAA8ABgnkA+VWALgAAAAA.Nanosec:BAAALgAECgEJAQAAAA==.Nansea:BAAALgAECgEJAgAAAA==.Nashalie:BAABLgAECn80AAIfAAkJsR66AQB6AgAfAAkJsR66AQB6AgAAAA==.Natedawg:BAAALgAECgUJCQAAAA==.',
Ne='Neezzdutzz:BAAALgAECgMJAwAAAA==.Nefele:BAABLgAECn8hAAIBAAkJ5RUWIwA8AgABAAkJ5RUWIwA8AgAAAA==.Nepheli:BAACLgAFFH8GAAICAAMJUxefVgDrAAACAAMJUxefVgDrAAAuAAQKf00AAgIACQlrJF4DAFIDAAIACQlrJF4DAFIDAAAA.Newrhu:BAAALgAECgYJBwAAAA==.Nexbasia:BAACLgAFFH8QAAIEAAMJnRLvAwDVAAAEAAMJnRLvAwDVAAAuAAQKf18AAwQACQnYHn0AAHICAAQACQnYHn0AAHICAAMAAgn2Apr6ABoAAAAA.',
Ni='Nickyboy:BAABLgAECn8lAAQbAAcJyiHhBQAKAgAbAAcJyiHhBQAKAgAfAAIJvg54BwFhAAAcAAEJrBd0PQA3AAAAAA==.Nightevel:BAAALgAECgUJBQAAAA==.Nihimetal:BAAALgAECgUJCAAAAA==.Nikash:BAABLgAECn80AAMIAAkJFBNVHADnAQAIAAkJFBNVHADnAQADAAYJ+QhgfwC8AAAAAA==.Nisato:BAAALgAECgUJBQAAAA==.',
No='Noctum:BAAALgAECgYJEAAAAA==.Nommei:BAAALgAECgcJEwAAAA==.Northic:BAAALgAECgYJBgABLgAECgkJNQAGAPEgAA==.Nortikolait:BAAALgAECgEJAQABLgAECgkJNQAGAPEgAA==.',
Ny='Nyriah:BAAALgAECgUJCwAAAA==.',
Ob='Obm:BAAALgAECgUJCwAAAA==.',
Oc='Octoface:BAAALgAECgYJBQAAAA==.Octt:BAACLgAFFH8HAAIfAAMJoRntagDuAAAfAAMJoRntagDuAAAuAAQKfyAAAh8ACQk5HFkEAJwBAB8ACQk5HFkEAJwBAAAA.',
Of='Offal:BAABLgAECn81AAQhAAYJjxVYAwATAQAXAAYJCAsJGAA5AQAhAAYJjxVYAwATAQAjAAEJJQV2swAjAAAAAA==.',
Ol='Olanna:BAAALgAECgYJDAAAAA==.Oldcannabis:BAAALgAECgQJCwAAAA==.',
Om='Ominis:BAAALgAECgUJBQAAAA==.',
Oo='Oomaw:BAAALgAECgMJBAAAAA==.',
Or='Orcal:BAACLgAFFH8gAAIiAAUJ/xj7KQAgAQAiAAUJ/xj7KQAgAQAuAAQKfx0AAiIACAn7GnQQAHECACIACAn7GnQQAHECAAAA.Ormie:BAAALgAECgQJBAAAAA==.Ornimus:BAABLgAECn8ZAAMOAAYJ0RJsIAAQAQAOAAYJ0RJsIAAQAQANAAQJEARkKAGJAAAAAA==.',
Ot='Otherrhu:BAAALgAECgUJBwAAAA==.',
Oz='Ozo:BAABLgAECn8dAAIFAAcJqBIgbQBnAQAFAAcJqBIgbQBnAQAAAA==.',
Pa='Paiva:BAAALgAECgUJCAAAAA==.Palandor:BAAALgADCgMJAwAAAA==.Pallyscorned:BAABLgAECn9FAAIOAAkJ/iHjAgD3AgAOAAkJ/iHjAgD3AgAAAA==.Pampas:BAABLgAECn8bAAMBAAkJkgSndAD/AAABAAkJkgSndAD/AAAVAAEJ5AFvwwAZAAAAAA==.Pandamonic:BAAALgAECgQJBAAAAA==.Paxdei:BAAALgAECgUJCQAAAA==.',
Pe='Ped:BAAALgAECgQJBgAAAA==.',
Ph='Phenixy:BAAALgAECgUJCwAAAA==.Phoebell:BAAALgAECgYJDQAAAA==.',
Pi='Pinkducky:BAABLgAECn8jAAIGAAcJDQZvFQCwAAAGAAcJDQZvFQCwAAAAAA==.',
Pl='Plen:BAACLgAFFH8FAAIGAAMJ9RCRRgCZAAAGAAMJ9RCRRgCZAAAuAAQKfy8AAxoACQm6H98BAM8BAAYACQmTHFo1AGECABoABgk/IN8BAM8BAAAA.',
Po='Ponder:BAAALgAECgYJCgAAAA==.Poppyseed:BAAALgAECgMJAwAAAA==.Poquads:BAAALgAECgQJBwAAAA==.',
Pr='Primaris:BAAALgAECgcJDAAAAA==.Prinnce:BAAALgAECgcJDgABLgAECgkJVAAKABokAA==.Príestatute:BAAALgAECgUJBQABLgAFFAMJCgAFACgUAA==.',
Pu='Pulmifinger:BAAALgAECgEJAQAAAA==.Punka:BAAALgAECgEJAQAAAA==.Purplesea:BAAALgADCgcJDQABLgAECgkJOgARAGYTAA==.',
Pv='Pve:BAAALgAECgcJCAAAAA==.',
Qi='Qilt:BAAALgADCgcJBwAAAA==.',
Qu='Quasar:BAABLgAECn8lAAIgAAkJmBgVQQAZAgAgAAkJmBgVQQAZAgAAAA==.',
Ra='Raaluur:BAAALgADCgUJBQAAAA==.Radra:BAABLgAECn88AAQQAAkJ5BHuAQAjAQAUAAkJfhG4GQCzAQAQAAcJxA3uAQAjAQACAAUJdAQLHwBPAAAAAA==.Raeku:BAABLgAECn8tAAImAAkJkCAUBgDCAgAmAAkJkCAUBgDCAgAAAA==.Rainee:BAAALgADCgYJBwAAAA==.Raja:BAAALgAECgUJDwAAAA==.Rathalo:BAAALgAECgQJBgAAAA==.Rav:BAAALgADCgUJBQAAAA==.Ravick:BAAALgADCgEJAQAAAA==.Razensetral:BAAALgAECggJCAAAAA==.Razzlor:BAAALgADCgUJBQAAAA==.',
Re='Reducto:BAABLgAECn8hAAMQAAYJhRXmFwDiAAACAAYJnBNxfgAjAQAQAAUJPxXmFwDiAAAAAA==.Reenailinefh:BAAALgADCgcJDgAAAA==.Relitha:BAAALgADCgUJCQAAAA==.Remeii:BAABLgAECn8iAAMBAAgJJghPgADgAAABAAcJtgRPgADgAAAVAAYJUQP9cQCVAAAAAA==.Retribution:BAABLgAECn85AAINAAkJ5hM9SADtAQANAAkJ5hM9SADtAQAAAA==.Reylexgt:BAAALgAECgEJAQAAAA==.',
Rh='Rhaenera:BAAALgAECgMJCgABLgAECgkJVAAKABokAA==.Rhage:BAAALgADCgkJCQAAAA==.',
Ri='Richcraniums:BAAALgADCgcJBwAAAA==.',
Ro='Roachers:BAAALgADCgIJAgAAAA==.Robomurph:BAAALgADCggJDwAAAA==.Rolas:BAAALgAECgYJAgAAAA==.Ronfax:BAACLgAFFH8nAAMBAAcJ0yFkAgAgAgABAAcJ0yFkAgAgAgAVAAIJxAWMUwBGAAAuAAQKfywAAwEACQm2IzwFAF8DAAEACQm2IzwFAF8DABUABgmeHN8qAJwBAAAA.Ronia:BAAALgADCgIJAgABLgAECgYJGQACALwcAA==.Rooss:BAAALgAECgcJEgAAAA==.Roqane:BAAALgAECgQJBAAAAA==.Roserade:BAAALgAECgkJEwAAAA==.Rothkin:BAAALgADCgMJAwAAAA==.Rotreiter:BAAALgADCgEJAQAAAA==.Rowdyredneck:BAAALgADCgMJAwABLgAECggJGQAKAGIXAA==.',
Ru='Rukea:BAAALgADCgkJCQAAAA==.Rul:BAAALgAFFAEJAQABLgAFFAQJEQAGAJ4gAA==.',
Ry='Ryllae:BAAALgAECgQJBQABLgAECgkJHgAUAFciAA==.Ryuusythe:BAAALgADCgcJBwAAAA==.Ryân:BAAALgADCgEJAQAAAA==.',
['Rì']='Rììdìì:BAAALgAECgcJBwABLgAFFAMJCgAFACgUAA==.',
Sa='Saara:BAAALgADCgEJAQAAAA==.Sackhammer:BAAALgAECgQJBAAAAA==.Saint:BAAALgAECgkJDwAAAA==.Salopard:BAAALgAECgIJAgAAAA==.Samson:BAABLgAECn8WAAQKAAYJLRzRIgCaAQAKAAYJLRzRIgCaAQALAAQJHA/fTgDFAAAWAAIJ3wpgqgBJAAABLgAECgUJCwAMAAAAAA==.Sanivan:BAABLgAECn8VAAIUAAcJ+hdxGgDvAQAUAAcJ+hdxGgDvAQAAAA==.Sanoan:BAAALgAECgQJBQAAAA==.Saori:BAAALgAECgEJAQAAAA==.Sappy:BAABLgAECn8aAAQeAAcJdR9BCQCuAQAeAAYJsh5BCQCuAQAlAAQJrxwzOwA/AQAnAAQJ8BLcCQDFAAABLgAFFAQJEQAGAJ4gAA==.Sarinae:BAABLgAECn8qAAQiAAkJeAf6BgDBAAAiAAgJzwX6BgDBAAAdAAEJGQ64BQArAAAkAAEJwAEQRAAfAAAAAA==.Sarmuc:BAABLgAECn8ZAAMYAAgJmw+8FwBMAQAYAAgJmw+8FwBMAQAVAAEJXwuesAAoAAAAAA==.Sarnluz:BAAALgAECgEJAQABLgAECggJEQAMAAAAAA==.Saryda:BAAALgAECgUJDQABLgAECgcJCAAMAAAAAA==.Sauda:BAAALgAECgEJAQAAAA==.Saurian:BAAALgADCgEJAQAAAA==.',
Sc='Schadoww:BAAALgAECggJDQABLgAFFAMJBQAGAPUQAA==.Scubagal:BAAALgAECgYJDQAAAA==.Scy:BAAALgAECggJDQAAAA==.Scythraza:BAABLgAECn80AAMiAAgJchp5AQDUAQAiAAgJchp5AQDUAQAkAAEJCQR9PgAqAAAAAA==.',
Se='Seablue:BAAALgAECgMJBQABLgAECgkJOgARAGYTAA==.Sedaleice:BAAALgAECgEJAQAAAA==.Sedge:BAAALgADCgEJAQAAAA==.Seedsprayer:BAAALgAECgYJDAAAAA==.Selara:BAAALgAECgMJAwAAAA==.Sellenah:BAABLgAECn8ZAAICAAYJvBzOXAByAQACAAYJvBzOXAByAQAAAA==.Sensu:BAAALgAECgcJEQAAAA==.Sensual:BAAALgAECgYJAwAAAA==.Sernian:BAAALgAFFAMJBAABLgAFFAUJHwANAPgjAA==.Seä:BAABLgAECn86AAIRAAkJZhMXHAAjAgARAAkJZhMXHAAjAgAAAA==.',
Sh='Shadoweave:BAABLgAECn8dAAIPAAkJqwfcMwBJAQAPAAkJqwfcMwBJAQAAAA==.Shampooshady:BAAALgAECgMJBAAAAA==.Shamtea:BAABLgAECn82AAIVAAkJJhR2AwB9AQAVAAkJJhR2AwB9AQAAAA==.Shandrin:BAAALgAECgEJAQAAAA==.Shapzan:BAAALgAECgcJEQAAAA==.Shareliss:BAAALgADCgYJBgAAAA==.Sharks:BAAALgAECgQJDwAAAA==.Shiik:BAAALgAECgYJBwABLgAECgcJGQARABIYAA==.Shivant:BAABLgAECn86AAMBAAkJSR2tFQCdAgABAAkJSR2tFQCdAgAVAAIJQwWemwBBAAAAAA==.Shmeegleroop:BAAALgAECgYJDgAAAA==.Shroomhunter:BAAALgAECgEJAQAAAA==.Shîvå:BAACLgAFFH8FAAIQAAIJpyF1AwCwAAAQAAIJpyF1AwCwAAAuAAQKfzEAAhAACQniID0CAOQCABAACQniID0CAOQCAAAA.',
Si='Sideburns:BAAALgAECgMJAwAAAA==.Silvertime:BAAALgADCgYJBwAAAA==.Sindice:BAAALgAECgYJCwABLgAFFAcJJwABANMhAA==.',
Sk='Skaa:BAAALgAECgEJAwAAAA==.',
Sl='Slammy:BAAALgAECgQJBAAAAA==.Slanesh:BAAALgAECgIJAgAAAA==.Slimpooshady:BAACLgAFFH8HAAIZAAMJvQwPDgCMAAAZAAMJvQwPDgCMAAAuAAQKfzQAAwMACQkWEn0oAA4CAAMACQkWEn0oAA4CABkACQmmEzcRANgBAAAA.Sloth:BAABLgAECn8tAAIaAAkJ9SCyAADGAgAaAAkJ9SCyAADGAgAAAA==.',
So='Solaspirus:BAABLgAECn8uAAMCAAkJ6BsZBQBqAQACAAkJ6BsZBQBqAQAQAAEJawxCNwAqAAAAAA==.Solinius:BAAALgAECgQJBQAAAA==.Sope:BAAALgAECgYJDQABLgAECggJDgAMAAAAAA==.Sorhtx:BAAALgAECgUJBwAAAA==.Soulomatic:BAAALgADCgcJBwAAAA==.',
Sp='Spectors:BAABLgAECn9AAAMcAAgJwBCqDwBjAQAcAAcJAxOqDwBjAQAfAAcJ5wNwwQDKAAAAAA==.Spekturx:BAAALgAECgEJAQAAAA==.Spideygirl:BAABLgAECn8WAAIRAAgJPxzPEQCFAgARAAgJPxzPEQCFAgAAAA==.Sprayinnseed:BAAALgAECgMJBAAAAA==.Sprayinseed:BAAALgADCgMJAwAAAA==.',
Sq='Squarepants:BAAALgAECgQJCQABLgAECgQJDwAMAAAAAA==.',
St='Stabon:BAABLgAECn8lAAIlAAkJcwlDHwCcAQAlAAkJcwlDHwCcAQAAAA==.Stalaediir:BAAALgADCgQJBAAAAA==.Stardre:BAAALgADCgQJBQAAAA==.Stevesmith:BAAALgAECgEJAgAAAA==.Stonedrage:BAAALgADCgEJAQAAAA==.Stormspirits:BAAALgADCgUJBQAAAA==.Sturdyy:BAAALgADCgMJAwAAAA==.Stãrkïllér:BAAALgADCgMJAwAAAA==.',
Su='Sugarmarks:BAAALgAECgYJDwAAAA==.',
Sw='Sweetstorm:BAABLgAECn9YAAIUAAkJIAuaBAAeAQAUAAkJIAuaBAAeAQAAAA==.',
Sy='Synvara:BAAALgADCgUJBQAAAA==.',
['Sê']='Sêphiroth:BAABLgAECn83AAIRAAkJWxeEFABqAgARAAkJWxeEFABqAgAAAA==.',
Ta='Taekoad:BAAALgADCgIJAgAAAA==.Tahlia:BAAALgAECgEJAQAAAA==.Tania:BAABLgAECn8aAAINAAgJsxMTXwCzAQANAAgJsxMTXwCzAQAAAA==.Taredelaria:BAAALgAECgEJAgAAAA==.Tarixx:BAABLgAFFH8GAAMNAAMJ/w5hJACjAAANAAIJQg5hJACjAAAOAAEJeRA0GgAqAAAAAA==.Tazanoth:BAACLgAFFH8IAAQFAAMJBBLAcQC8AAAFAAMJ0Q/AcQC8AAAmAAIJKQ7lKwCDAAASAAEJTArEJgBPAAAuAAQKfyEAAyYACQmaG4kPADYCACYACQmQGokPADYCABIABglBGtYwALABAAAA.',
Te='Teasa:BAABLgAECn9CAAIFAAkJ2RmKIQBfAgAFAAkJ2RmKIQBfAgAAAA==.Tekeelà:BAACLgAFFH8RAAQFAAYJixlDAgB7AQAFAAYJixlDAgB7AQASAAEJVgAiLgA1AAAmAAEJhAF0OAAqAAAuAAQKfzIABAUACQl2IaMVAIoCAAUACQkHH6MVAIoCACYACQm6GJ8PADUCABIABwm3EeY5AHoBAAAA.Tekkamaki:BAAALgADCgcJCAAAAA==.',
Th='Thalion:BAABLgAECn8cAAMFAAYJdwOZwwDAAAAFAAYJdwOZwwDAAAAmAAUJcgF+VQBXAAAAAA==.Theenna:BAAALgAECgYJDAAAAA==.Thetodd:BAAALgAECgIJAgAAAA==.Thianna:BAABLgAECn8oAAMRAAkJyBn5GwAkAgARAAkJyBn5GwAkAgANAAcJnhCEHQCNAAAAAA==.Thiculuskage:BAABLgAECn8YAAIRAAkJvB77BwAMAwARAAkJvB77BwAMAwAAAA==.Thinkso:BAAALgADCgcJGwAAAA==.Thobu:BAAALgAECgcJCwAAAA==.Thodos:BAAALgADCgEJAQAAAA==.Thornscale:BAABLgAECn9OAAQiAAkJ3ho3EQBcAgAiAAkJ3ho3EQBcAgAdAAYJbhYnAQAsAQAkAAYJogvrKAAsAQAAAA==.Thorrent:BAAALgADCgcJDQAAAA==.',
Ti='Tigolcrittys:BAAALgAECgcJEgABLgAFFAMJCgAFACgUAA==.Timeforloads:BAABLgAECn8rAAMIAAkJ8hYdNABIAQAIAAcJOhUdNABIAQADAAYJxB/wBAA7AQAAAA==.Tirria:BAAALgAECgEJAQAAAA==.',
To='Tolk:BAAALgAECgcJEQAAAA==.Tomzombe:BAAALgAECgQJBgAAAA==.Totem:BAABLgAECn8WAAIVAAgJvQu3RQAdAQAVAAgJvQu3RQAdAQAAAA==.Totenz:BAAALgADCgYJBgAAAA==.',
Tr='Traveler:BAAALgAECgIJAgAAAA==.Trickyflamom:BAABLgAECn8aAAIgAAcJzByEBQC6AQAgAAcJzByEBQC6AQABLgAFFAQJIgAgAPYaAA==.Troloq:BAABLgAECn85AAQcAAkJfx2BCADgAQAfAAgJHhuKNwD7AQAcAAgJWReBCADgAQAbAAYJTRoEFAAQAQAAAA==.Trondoom:BAAALgADCgYJBgAAAA==.',
Tu='Tugboattimmy:BAAALgAECgEJAQAAAA==.Tulisha:BAAALgAECgUJCgAAAA==.Turero:BAAALgAECgQJCAABLgAFFAQJGAADAEIRAA==.Turger:BAAALgAECgUJCAABLgAECgkJEAAMAAAAAA==.Turinnii:BAAALgADCgcJBwAAAA==.',
Ul='Uller:BAABLgAECn8oAAIgAAkJDhrQMABWAgAgAAkJDhrQMABWAgAAAA==.',
Um='Umbrafang:BAAALgAECgEJBAAAAA==.',
Un='Unholyspirit:BAAALgAECgQJDwAAAA==.',
Va='Vahlorraa:BAABLgAECn8mAAIRAAYJ6RGvBAArAQARAAYJ6RGvBAArAQAAAA==.Vaimei:BAACLgAFFH8GAAIfAAMJQBXNIADVAAAfAAMJQBXNIADVAAAuAAQKfzcAAxsACQn4Ii8CAKICABsACAk9Iy8CAKICAB8ACAkDID8WAJ8CAAAA.Valashune:BAAALgADCgEJAQAAAA==.Valsilla:BAAALgAECgYJBgABLgAECgkJHgAUAFciAA==.Vapor:BAABLgAECn8wAAIeAAkJyxxHAAA4AgAeAAkJyxxHAAA4AgAAAA==.Varanius:BAAALgAECgEJAgAAAA==.',
Ve='Veebes:BAAALgAECggJCAAAAA==.Veebs:BAABLgAECn8dAAMjAAgJqhPeBgAJAQAjAAgJqhPeBgAJAQAhAAEJAAAySAAuAAAAAA==.Velóran:BAAALgADCgcJBwAAAA==.Vendola:BAABLgAECn8gAAIgAAgJaQboqgAqAQAgAAgJaQboqgAqAQAAAA==.Vento:BAABLgAECn8VAAIGAAgJjxWuYgCjAQAGAAgJjxWuYgCjAQAAAA==.Verité:BAABLgAECn8UAAMdAAgJ8gwzDwAXAQAdAAcJdg4zDwAXAQAiAAcJfQmBTgD0AAAAAA==.Veterpeinss:BAAALgADCggJDgAAAA==.',
Vi='Viento:BAAALgADCgcJBwAAAA==.Villiveil:BAAALgAECgEJAQABLgAFFAQJBgANAJoZAA==.Vintersorg:BAAALgAECgUJCQAAAA==.Virauca:BAABLgAECn9MAAICAAkJjhYtLgAOAgACAAkJjhYtLgAOAgAAAA==.Viuhl:BAAALgADCgQJAwAAAA==.',
Vo='Vodgrax:BAAALgAECgIJAgAAAA==.Voidstar:BAAALgAECgUJDAAAAA==.Voltimand:BAAALgAECgEJAQABLgAFFAMJCgABAGcPAA==.',
Vv='Vvicked:BAABLgAECn8gAAIGAAgJrCI8FwC7AgAGAAgJrCI8FwC7AgAAAA==.',
Vy='Vynesta:BAABLgAECn8eAAIUAAkJVyKvAwAZAwAUAAkJVyKvAwAZAwAAAA==.',
Wa='Wala:BAAALgAECgcJDAAAAA==.Wamoo:BAAALgAECgEJAgAAAA==.Wanagi:BAAALgADCgMJAwAAAA==.Wankz:BAAALgAECgkJEgAAAA==.Wankzerkin:BAAALgADCgEJAQAAAA==.Warriorguyes:BAABLgAECn8fAAIjAAkJtSKbBwDlAgAjAAkJtSKbBwDlAgAAAA==.',
We='Weyna:BAABLgAECn84AAMWAAgJ3hHVMgCsAQAWAAgJ3hHVMgCsAQALAAYJVAmnTQDJAAABLgAFFAYJHwAkAO8UAA==.',
Wh='Whisperingei:BAAALgAECgYJCgAAAA==.Whomper:BAAALgAECgYJDAAAAA==.Whpheonix:BAAALgADCgkJEAAAAA==.',
Wi='Widowx:BAACLgAFFH8JAAMVAAMJaw/JEwC4AAAVAAMJaw/JEwC4AAABAAEJEgEjjwAgAAAuAAQKfzQAAhUACQnIHBwCAOIBABUACQnIHBwCAOIBAAAA.Winfurdal:BAAALgADCggJCAAAAA==.',
Wo='Womphunt:BAABLgAECn8WAAIFAAcJlBqgPgDnAQAFAAcJlBqgPgDnAQABLgAECgkJLAATABkhAA==.',
Wr='Wrandohunt:BAAALgAECgEJBAAAAA==.Wrandowdemon:BAAALgADCgcJBwAAAA==.Wreckitrandy:BAAALgAECgEJAQAAAA==.Wryn:BAAALgAECgkJEQABLgAFFAMJBQAGAPUQAA==.',
Wu='Wulyn:BAAALgAECgcJDAAAAA==.',
Wy='Wylla:BAAALgAECgYJEgAAAA==.',
Xa='Xalethra:BAABLgAECn87AAICAAkJ8CQ7BQA0AwACAAkJ8CQ7BQA0AwAAAA==.Xaltheris:BAAALgAECgUJBgAAAA==.',
Xe='Xelha:BAAALgAECgYJBgAAAA==.Xenophobias:BAABLgAECn8XAAMaAAcJuxA3BQDaAAAaAAYJahM3BQDaAAAGAAIJUgMdowEdAAAAAA==.',
Xh='Xhosen:BAABLgAFFH8HAAIGAAIJEhJ3SwCMAAAGAAIJEhJ3SwCMAAAAAA==.',
Xr='Xratedmurdaa:BAAALgAECgEJAQAAAA==.',
Xs='Xsuns:BAABLgAECn9JAAIDAAkJYxqqHQBZAgADAAkJYxqqHQBZAgAAAA==.',
Ya='Yarloon:BAAALgADCgcJBwAAAA==.',
Yt='Ytsirk:BAAALgADCgYJBgAAAA==.',
Yv='Yve:BAAALgAECgUJDQAAAA==.',
Za='Zaharian:BAAALgAECgEJAQAAAA==.Zalajin:BAAALgAECgQJBAAAAA==.Zalila:BAAALgADCgYJBgAAAA==.Zanasi:BAEALgAECgcJBwABLgAFFAMJEwAFAKUkAA==.Zarayndia:BAAALgAECgYJCAAAAA==.',
Ze='Zeddicus:BAABLgAECn8tAAMcAAkJ9wi2DgBwAQAcAAkJfAi2DgBwAQAfAAUJDgXk8gB8AAAAAA==.Zendragan:BAACLgAFFH8HAAIWAAMJzxAbQQCfAAAWAAMJzxAbQQCfAAAuAAQKfx4AAhYACQlOGOcXAFkCABYACQlOGOcXAFkCAAAA.Zerhas:BAAALgAECgEJAwAAAA==.',
Zo='Zoe:BAAALgAECgQJCQAAAA==.Zoidz:BAAALgAECggJDAAAAA==.Zombiemagic:BAAALgADCgMJAwAAAA==.Zombruh:BAAALgAECgEJAQAAAA==.Zomgimlothar:BAAALgADCgIJAwAAAA==.Zoomy:BAAALgAECgQJCwAAAA==.',
Zy='Zyntarum:BAAALgADCgEJAQAAAA==.Zythopoios:BAAALgAFFAEJAgAAAA==.',
Zz='Zzilladi:BAABLgAFFH8SAAMTAAYJ1RkTCQC8AQATAAYJ1RkTCQC8AQAPAAEJAACzRAAAAAAAAA==.Zzilladinzz:BAACLgAFFH8UAAINAAUJjSBuMQBOAQANAAUJjSBuMQBOAQAuAAQKfyIAAg0ACQkIIwsSAAIDAA0ACQkIIwsSAAIDAAAA.',
['Ëu']='Ëulogy:BAAALgAECgcJEQABLgAFFAIJBQAQAKchAA==.',
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
