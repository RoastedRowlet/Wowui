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

local lookup = {'Shaman-Restoration','DemonHunter-Devourer','Druid-Restoration','Druid-Feral','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Priest-Discipline','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Priest-Shadow','DemonHunter-Vengeance','Paladin-Holy','Hunter-Marksmanship','Priest-Holy','DemonHunter-Havoc','Shaman-Elemental','Monk-Mistweaver','Warrior-Arms','Evoker-Preservation','Shaman-Enhancement','Druid-Guardian','DeathKnight-Blood','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Rogue-Assassination','Warlock-Demonology','Mage-Frost','Warrior-Protection','Evoker-Augmentation','Warrior-Fury','Rogue-Subtlety','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=46,date='2026-07-12',data={Aa='Aarmorr:BAABLgAECn9SAAIBAAkJmhk4FgCYAgABAAkJmhk4FgCYAgAAAA==.Aatus:BAAALgAECgYJBwAAAA==.',
Ab='Absoul:BAAALgAECgQJBAAAAA==.Abyssidia:BAAALgAECgIJAgAAAA==.',
Ac='Acinianis:BAAALgAECgEJAQAAAA==.Acinthos:BAAALgAECgQJBgAAAA==.',
Ad='Adiros:BAAALgADCgUJBQAAAA==.',
Ae='Aechelus:BAAALgADCgEJAQABLgAECggJFQACAAceAA==.Aedelas:BAAALgAECgIJBAAAAA==.Aeloriá:BAABLgAECn9NAAMDAAkJxSBxBwBAAwADAAkJxSBxBwBAAwAEAAEJFQGgOwAPAAAAAA==.Aelyra:BAAALgAECggJEgAAAA==.',
Ag='Agrosa:BAAALgAECgYJBgAAAA==.',
Ai='Aimeeiove:BAAALgAECgYJCgAAAA==.Airad:BAAALgADCgUJBgAAAA==.Airoldeel:BAAALgAECgEJAQAAAA==.',
Al='Alcarza:BAAALgAECgMJBQAAAA==.Alchon:BAABLgAECn8kAAIFAAkJ6xqGLwAeAgAFAAkJ6xqGLwAeAgAAAA==.Aldera:BAABLgAECn88AAIBAAkJwgmuCgAsAQABAAkJwgmuCgAsAQAAAA==.Aledish:BAAALgAECgEJAgAAAA==.Alicien:BAABLgAECn8jAAMGAAkJwRwpSADqAQAGAAkJwRwpSADqAQAHAAEJyhBgFgA3AAAAAA==.Alista:BAAALgAECgYJCwAAAA==.Alladon:BAAALgADCgUJBQAAAA==.Allykat:BAABLgAECn9OAAMDAAgJJBcNAwDiAQADAAgJJBcNAwDiAQAIAAYJRxEIPwATAQAAAA==.Alorris:BAAALgAECgQJBgABLgAECgkJGQAJAFggAA==.Alunathsong:BAAALgADCgcJBwAAAA==.Alvagíngras:BAAALgAECgkJEAAAAA==.Alyra:BAAALgAECgYJBgAAAA==.',
Am='Amaith:BAAALgAFFAIJBAAAAA==.Amantillado:BAAALgAECgQJBAABLgAECggJGQAKAGIXAA==.Amata:BAAALgAECgUJCwAAAA==.Amelianne:BAAALgAECgcJEQAAAA==.Amiria:BAAALgAECgYJBgAAAA==.Ammastary:BAAALgAECgQJBgAAAA==.Ammonfrey:BAAALgAECgEJAQAAAA==.Amorfati:BAAALgAECgEJAQAAAA==.',
An='Ananiel:BAAALgADCgQJBQABLgAECgkJLwALAA8bAA==.Andragos:BAAALgAECgQJCgAAAA==.Andrea:BAABLgAECn9KAAIEAAkJYR3oBACrAgAEAAkJYR3oBACrAgAAAA==.Andrelia:BAAALgADCgkJDwAAAA==.Angelec:BAAALgAECgEJAQAAAA==.Angelex:BAAALgAECgEJAQAAAA==.Anthria:BAAALgAECgcJEAAAAA==.',
Ao='Aoon:BAAALgAECgEJAQAAAA==.',
Ap='Apoleth:BAAALgADCgMJAwAAAA==.',
Aq='Aqules:BAAALgADCgEJAgAAAA==.',
Ar='Arcapeligo:BAAALgAECgEJAgAAAA==.Archonsfury:BAAALgAECggJDwAAAA==.Arilyn:BAAALgAECgMJAwAAAA==.Array:BAAALgAECgUJBQAAAA==.',
As='Asath:BAAALgAECgYJDAAAAA==.Ascended:BAAALgAECgEJAgABLgADCgkJCQAMAAAAAA==.Asheye:BAAALgAECgkJCgABLgAFFAMJBQAGAPUQAA==.Ashuranadi:BAAALgADCgcJBwAAAA==.Askir:BAAALgADCgMJAwAAAA==.Asnew:BAAALgAECgkJEQAAAA==.Asura:BAAALgAECggJDgAAAA==.Asyllaa:BAABLgAECn8eAAMNAAkJFx+LLABPAgANAAcJOyOLLABPAgAOAAYJ9hLNHwAWAQAAAA==.',
At='Athelstan:BAAALgADCgIJAgAAAA==.Atnawuerus:BAAALgAECgEJAQAAAA==.Atonement:BAABLgAECn8aAAMJAAkJJBqFFAA5AgAJAAgJNh2FFAA5AgAPAAQJLgkTcwBbAAABLgAFFAMJBgAQAOkhAA==.Atullua:BAAALgADCgEJAQAAAA==.',
Au='Aumaril:BAABLgAECn8dAAMRAAgJiBcrGwArAgARAAgJiBcrGwArAgANAAgJNxRyZACnAQAAAA==.Auralynn:BAABLgAECn8qAAINAAkJUAl/kgBOAQANAAkJUAl/kgBOAQAAAA==.',
Av='Avathar:BAAALgAECgMJBgAAAA==.Averus:BAABLgAECn9SAAIIAAkJuhLJHQDaAQAIAAkJuhLJHQDaAQAAAA==.',
Az='Azariel:BAABLgAECn8+AAINAAkJ5BPtDgAnAQANAAkJ5BPtDgAnAQAAAA==.Azenwraith:BAAALgADCgkJCQAAAA==.Azuriah:BAABLgAECn9MAAMOAAkJ6B3/BQCLAgAOAAkJIB3/BQCLAgANAAEJXyHCTgFfAAAAAA==.',
Ba='Baane:BAAALgAECgQJBwABLgAECgcJEQAMAAAAAA==.Babnik:BAEBLgAECn8YAAMFAAkJZBOPDQBDAQAFAAkJZBOPDQBDAQASAAIJPw0IMABYAAAAAA==.Bagel:BAACLgAFFH8eAAMRAAUJHCNeDQDhAQARAAUJHCNeDQDhAQANAAQJaQfcLgC2AAAuAAQKfxkAAxEACAmCH1AmAPYBABEACAmCH1AmAPYBAA0AAQnkCrKpASsAAAAA.Baldwin:BAAALgAECgUJBQAAAA==.Ballbreaker:BAAALgAECgQJBAAAAA==.Baminenherb:BAAALgADCgUJBQAAAA==.Bazluz:BAAALgADCgIJAwAAAA==.',
Be='Bearlysoberr:BAAALgAECgUJBQAAAA==.Bedhead:BAABLgAECn9DAAQJAAkJpRdwEQBdAgAJAAkJ7BZwEQBdAgATAAMJFBx6VQDgAAAPAAEJKwrXjgAsAAAAAA==.Bedrocked:BAAALgAECgIJAwAAAA==.Belaim:BAAALgAECgIJAgAAAA==.Belovis:BAACLgAFFH8fAAINAAYJiCQvDQBqAQANAAYJiCQvDQBqAQAuAAQKfyYAAg0ACQk0JOgMACYDAA0ACQk0JOgMACYDAAAA.Berathor:BAAALgAECgkJEwAAAA==.Betsea:BAAALgAECgUJBQABLgAECgkJOgARAGYTAA==.',
Bi='Bidoof:BAABLgAECn80AAIUAAkJfQ+7BABDAQAUAAkJfQ+7BABDAQAAAA==.Bigblunt:BAAALgADCgcJEgAAAA==.Bigear:BAAALgAECgQJBAAAAA==.Bigjohnii:BAAALgADCgcJBwAAAA==.Birdi:BAAALgAECgEJAwAAAA==.Bitemarks:BAAALgADCgcJDgAAAA==.',
Bl='Blackcoat:BAAALgAECgYJDwAAAA==.',
Bo='Boggrog:BAAALgAECgYJCQABLgAECgUJCwAMAAAAAA==.Bolz:BAAALgAECgMJAwAAAA==.Boosch:BAAALgADCgIJAgAAAA==.Bosshog:BAABLgAECn80AAIVAAkJpAvuNgBeAQAVAAkJpAvuNgBeAQAAAA==.Bowgobrr:BAABLgAECn8qAAMSAAgJ4xXlDgBvAQASAAgJ4xXlDgBvAQAFAAYJ2QpW3QCTAAABLgAFFAgJJwAFALgSAA==.',
Br='Braelyne:BAABLgAECn8WAAINAAYJdR3JXwDEAQANAAYJdR3JXwDEAQAAAA==.Brasnite:BAAALgADCgEJAQAAAA==.Brewrock:BAAALgAECgQJCAAAAA==.Brewtilus:BAAALgADCgkJDgAAAA==.Brolaf:BAAALgAECgUJBQAAAA==.Broseidon:BAAALgAECgcJEQAAAA==.',
Bu='Buffsalot:BAAALgAECgUJDgAAAA==.Buffwarlock:BAAALgAECgcJBwAAAA==.Bullbatoo:BAAALgAECgEJAQAAAA==.Burlycheeks:BAABLgAECn85AAINAAkJPCCTGACwAgANAAkJPCCTGACwAgAAAA==.',
Ca='Caliista:BAAALgADCggJCAAAAA==.Carlitocool:BAAALgADCgIJAgAAAA==.Carraxus:BAAALgAECgQJDAAAAA==.Cassidyn:BAAALgADCgcJCAAAAA==.Castle:BAABLgAECn8YAAMNAAcJsB09bwCQAQANAAYJ+Bs9bwCQAQARAAYJZwlfCQC8AAAAAA==.Catsinhats:BAAALgAECgQJBAABLgAFFAQJFAAGAC8OAA==.Catsneverdie:BAAALgAFFAEJAQABLgAFFAQJFAAGAC8OAA==.Catzinhatz:BAABLgAECn8YAAICAAcJAgq/jgADAQACAAcJAgq/jgADAQABLgAFFAQJFAAGAC8OAA==.',
Ce='Cecelya:BAABLgAECn9AAAQTAAkJ5RlLFwAUAgATAAkJ5RlLFwAUAgAPAAcJNhGCNABGAQAJAAMJUw1iXACOAAAAAA==.Celibate:BAAALgAECgUJBgAAAA==.Celothor:BAAALgADCgYJBgAAAA==.Celticmoon:BAAALgADCgQJBAAAAA==.',
Ch='Cherlia:BAABLgAECn8cAAIVAAYJIhO2RQAyAQAVAAYJIhO2RQAyAQABLgAECgkJHgAUAFciAA==.Chillykiller:BAAALgAECgYJBwABLgAECgkJHgAUAFciAA==.Chiva:BAAALgAECgQJBAABLgAECgkJOgABAEkdAA==.Chivactdl:BAAALgAECgMJBAABLgAECgkJOgABAEkdAA==.Chivalt:BAAALgAECgEJAQABLgAECgkJOgABAEkdAA==.Chonch:BAAALgAECgIJAgAAAA==.Chozen:BAAALgAECggJCwAAAA==.Chunknoriss:BAABLgAECn8vAAMWAAYJYiD3HQApAgAWAAYJYiD3HQApAgAKAAMJWwWbdwBhAAABLgAECgkJOgABAEkdAA==.',
Ci='Cigarettes:BAABLgAECn8XAAIXAAYJsRV1BADwAAAXAAYJsRV1BADwAAAAAA==.',
Cl='Claudiuss:BAAALgAECgYJDAABLgAFFAMJCgABAGcPAA==.Clurefu:BAABLgAECn84AAMWAAkJvCEQBQBaAwAWAAkJvCEQBQBaAwAKAAMJ5BZVWACuAAABLgAFFAIJCQADAFsZAA==.Clurelock:BAACLgAFFH8JAAIDAAIJWxlkGQCEAAADAAIJWxlkGQCEAAAuAAQKfzQAAgMACQktIi4EAHsDAAMACQktIi4EAHsDAAAA.Cluremage:BAAALgAECgYJEQAAAA==.Clurethyr:BAABLgAECn8gAAIYAAgJUR9aAADHAgAYAAgJUR9aAADHAgAAAA==.',
Co='Cobblestone:BAAALgAECgIJAgAAAA==.Codenameknd:BAAALgAECgIJAgAAAA==.Comsuck:BAAALgAECgcJEQAAAA==.Conchobhar:BAABLgAECn8VAAIWAAkJlBoMGgBHAgAWAAkJlBoMGgBHAgAAAA==.Constella:BAAALgADCgYJCQAAAA==.Coppertan:BAAALgAECgMJBQAAAA==.Coralyne:BAAALgADCgEJAQAAAA==.Corrosion:BAABLgAECn8uAAIZAAkJCh6HBACnAgAZAAkJCh6HBACnAgAAAA==.',
Cr='Crazyshammy:BAAALgAECgkJEgAAAA==.Crommash:BAAALgAECgcJCgAAAA==.Crono:BAAALgAECgQJCQAAAA==.Crunchynuget:BAABLgAECn8pAAINAAkJbSCBAgCqAgANAAkJbSCBAgCqAgABLgAFFAUJGQANAHYjAA==.',
Ct='Cthuwu:BAAALgAECgMJAgABLgAFFAYJEgAFAIsZAA==.',
Cu='Cujotaro:BAAALgAECgEJAgAAAA==.Cumberdale:BAAALgAECgUJBQAAAA==.',
Cv='Cvhamster:BAAALgAECgQJCgAAAA==.',
Cy='Cybeast:BAABLgAECn81AAMEAAkJkh54BAC4AgAEAAkJhB54BAC4AgAaAAUJFRjFAwBhAQAAAA==.Cynortas:BAAALgAECgIJBgAAAA==.',
Da='Daciana:BAABLgAECn8gAAIFAAkJXhBUEgAOAQAFAAkJXhBUEgAOAQAAAA==.Dados:BAABLgAECn8wAAMTAAkJXh5tDgCBAgATAAkJXh5tDgCBAgAPAAEJsBRKgAA9AAAAAA==.Daeghun:BAAALgAECgIJBQAAAA==.Dahleigh:BAAALgADCgkJDQAAAA==.Dakanar:BAAALgAECgQJCgAAAA==.Dambrien:BAAALgAECgUJBQAAAA==.Daravus:BAAALgAECgUJCAAAAA==.Darkfox:BAAALgAECgEJAQAAAA==.Darkhazel:BAAALgAECgEJAQAAAA==.Darkkromdor:BAABLgAECn8zAAINAAkJtR/SFwC0AgANAAkJtR/SFwC0AgAAAA==.Darloct:BAAALgAECgcJEgAAAA==.Dazzlor:BAAALgADCggJCAAAAA==.',
De='Deadelff:BAABLgAECn8kAAMCAAgJ2hZHYwBhAQAUAAYJexvxJwCDAQACAAgJQg9HYwBhAQAAAA==.Deadholypaly:BAAALgADCgEJAwAAAA==.Deadlifts:BAAALgAECgQJCQAAAA==.Deadlighted:BAAALgADCgcJDgABLgAECggJJAACANoWAA==.Deadslinger:BAAALgADCgYJDAAAAA==.Deadtotem:BAAALgADCgkJCQABLgAECggJJAACANoWAA==.Deammon:BAAALgAECgEJAQAAAA==.Deathcat:BAACLgAFFH8UAAIGAAQJLw6QOgDUAAAGAAQJLw6QOgDUAAAuAAQKfzsAAgYACQmjFgc4AB8CAAYACQmjFgc4AB8CAAAA.Deathkiss:BAAALgAECgYJEgAAAA==.Deathrat:BAAALgADCgUJBgAAAA==.Deathrixx:BAABLgAFFH8RAAQGAAUJZx4JVABKAQAGAAUJQh4JVABKAQAHAAIJhB3QHACdAAAbAAEJIBhWPABEAAAAAA==.Deathshadowx:BAAALgAECgUJCwAAAA==.Delryth:BAAALgAECgQJBAAAAA==.Demonkoh:BAAALgAECgUJCAAAAA==.',
Df='Dfault:BAAALgADCgEJAQAAAA==.',
Di='Discharged:BAAALgAECgQJBAABLgAECggJGQAKAGIXAA==.',
Dk='Dkdeathblade:BAAALgAECgEJAQAAAA==.Dkpheonix:BAABLgAECn80AAIPAAkJ6xUOBQBPAQAPAAkJ6xUOBQBPAQAAAA==.',
Do='Dolemite:BAABLgAECn9GAAMWAAcJHhYdLwC/AQAWAAcJHhYdLwC/AQAKAAcJYxkdAgC8AQAAAA==.Donalbain:BAACLgAFFH8KAAIBAAMJZw+8UwCqAAABAAMJZw+8UwCqAAAuAAQKfzAAAgEACQkCHvsBAIwCAAEACQkCHvsBAIwCAAAA.Dotdotgoose:BAAALgAECgQJCAAAAA==.',
Dr='Draconz:BAAALgAECgIJAgABLgAECgYJEQAMAAAAAA==.Draganpriest:BAABLgAFFH8IAAIJAAMJCA71HAB6AAAJAAMJCA71HAB6AAAAAA==.Draganussy:BAAALgADCgEJAQAAAA==.Draggo:BAAALgAECgEJAQAAAA==.Drakkira:BAAALgADCgYJBgAAAA==.Draxon:BAAALgAECgEJAQAAAA==.Dremar:BAABLgAECn8eAAMcAAkJHQ9hAwANAQAcAAgJmA1hAwANAQAdAAYJRAyRGQDXAAAAAA==.Druc:BAAALgAECgEJAgAAAA==.',
Du='Durock:BAAALgAECgMJBAAAAA==.',
Dy='Dynaris:BAAALgADCgMJAwAAAA==.',
Ei='Eianna:BAAALgAECgEJAQAAAA==.',
El='Elcachazo:BAAALgAECgIJAgAAAA==.Eldinn:BAAALgADCgcJBgAAAA==.Elenora:BAAALgAECgMJAwAAAA==.Elidor:BAAALgAECgYJDwAAAA==.Ellalangley:BAAALgAECgIJAwABLgAFFAMJBQAGAPUQAA==.Elthelas:BAAALgADCgEJAQAAAA==.Eluneatic:BAAALgADCggJCgAAAA==.Elyssaris:BAABLgAECn84AAIbAAkJ4xoyDgAnAgAbAAkJ4xoyDgAnAgAAAA==.Elzulkin:BAAALgADCgcJCgAAAA==.',
Em='Emmdeath:BAABLgAECn8YAAIGAAYJ7QNWDgGaAAAGAAYJ7QNWDgGaAAAAAA==.Emmils:BAABLgAECn8+AAIIAAkJfA1uKgCBAQAIAAkJfA1uKgCBAQAAAA==.Emìly:BAABLgAECn9VAAQKAAkJGiQiAwAyAwAKAAkJGiQiAwAyAwAWAAkJCxaKHwAeAgALAAUJRRUqRgDiAAAAAA==.',
En='Enderelvarg:BAABLgAFFH8FAAIeAAUJbw9TBQARAQAeAAUJbw9TBQARAQAAAA==.Endmicrobuys:BAAALgADCgUJBQAAAA==.Entaria:BAACLgAFFH8GAAINAAQJmhmFMQBOAQANAAQJmhmFMQBOAQAuAAQKf0EABA0ACQk7IYMOAPICAA0ACQk7IYMOAPICAA4ABwkxH24NAO4BABEABgm1DGJbAMgAAAAA.',
Eo='Eox:BAAALgADCgMJAwAAAA==.',
Ep='Episkey:BAABLgAECn8gAAMIAAkJMhKOJgCZAQAIAAkJMhKOJgCZAQADAAQJdRcgYQASAQAAAA==.',
Er='Erindaglaze:BAAALgADCgQJBQAAAA==.Erissae:BAAALgADCgEJAgAAAA==.Eropor:BAABLgAECn8iAAMWAAYJexPyQQBlAQAWAAYJexPyQQBlAQAKAAMJYQbMigBHAAABLgAFFAQJGAADAEIRAA==.Eroversion:BAACLgAFFH8YAAMDAAQJQhFrMwDgAAADAAQJQhFrMwDgAAAIAAEJtwHmKAAgAAAuAAQKf1YABQMACQlCHq8XAIkCAAMACQlCHq8XAIkCAAgABAkIFj5UANUAAAQAAwm4DUszAJEAABoAAQkAAFWVAAAAAAAA.',
Es='Esmay:BAABLgAECn8fAAIVAAkJHRRNIADhAQAVAAkJHRRNIADhAQAAAA==.Eso:BAAALgADCgYJCwAAAA==.',
Et='Ethren:BAABLgAECn9RAAIfAAkJ2RgJBABeAgAfAAkJ2RgJBABeAgAAAA==.',
Eu='Eudeyrn:BAAALgAECgYJAwAAAA==.',
Ev='Evilrepu:BAAALgAECgEJAQAAAA==.',
Ey='Eyebrows:BAAALgAECgIJAgAAAA==.',
Ez='Ezikarridge:BAAALgAECgEJAQAAAA==.',
Fa='Faker:BAAALgADCgEJAQAAAA==.Falcone:BAAALgAECgMJBgAAAA==.',
Fe='Felbolter:BAAALgAECgEJBAAAAA==.Feliri:BAAALgAECggJDwAAAA==.',
Fi='Filgulfin:BAABLgAECn9ZAAMFAAkJBCC8EADLAgAFAAkJBCC8EADLAgASAAgJgRDREwAkAQAAAA==.Finkate:BAABLgAECn8XAAIFAAgJHA4FYwB/AQAFAAgJHA4FYwB/AQAAAA==.Firebad:BAABLgAECn8wAAMdAAkJpxy5AgCFAgAdAAkJpxy5AgCFAgAgAAYJHwrG5ACTAAAAAA==.Firebringer:BAABLgAECn9VAAICAAkJ9A7jSgCmAQACAAkJ9A7jSgCmAQAAAA==.Fistokaestey:BAAALgADCgkJEgABLgAECgkJIwAhANUXAA==.',
Fl='Flaakk:BAAALgADCgcJBwAAAA==.Flamehunter:BAABLgAECn8iAAMCAAkJMRqEHACnAgACAAkJcRmEHACnAgAUAAcJLRdgJACaAQAAAA==.Flo:BAABLgAECn9aAAMPAAkJhxwZCwCeAgAPAAkJhxwZCwCeAgATAAMJSAcyWAB5AAAAAA==.Floki:BAABLgAECn8UAAIiAAkJqhJnHQBKAQAiAAkJqhJnHQBKAQAAAA==.Flora:BAAALgAECgQJBAAAAA==.Flowing:BAABLgAECn8wAAIjAAkJyxnXAQDMAQAjAAkJyxnXAQDMAQAAAA==.',
Fo='Foods:BAACLgAFFH8VAAMkAAMJfhMDHQCYAAAkAAMJfhMDHQCYAAAiAAIJBgutEgBtAAAuAAQKf3UABCQACQlmHq4BAEwCACQACQlmHq4BAEwCACIACAlkFeACAGEBABcAAwnoDE0wAHUAAAAA.Foofsmash:BAAALgADCgUJBgAAAA==.',
Fr='Fripouille:BAAALgADCgMJAwAAAA==.',
Fu='Fustín:BAAALgAECgYJEgAAAA==.Fuzzyewok:BAAALgAECgYJEwAAAA==.',
['Fø']='Føøds:BAAALgADCgMJAwAAAA==.',
Ga='Gaboo:BAAALgAECgkJEwAAAA==.Garfman:BAAALgAFFAEJAQAAAA==.',
Gb='Gb:BAACLgAFFH8HAAIRAAYJExDZHgAmAQARAAYJExDZHgAmAQAuAAQKfxQAAhEABwknIYUSAH0CABEABwknIYUSAH0CAAEuAAUUBAkNAA8A8hoA.',
Gh='Ghostinhale:BAABLgAECn8dAAIGAAcJ2RYfDAApAQAGAAcJ2RYfDAApAQAAAA==.',
Gi='Gibbshole:BAAALgADCgcJBwAAAA==.Gilorion:BAABLgAECn8XAAIFAAkJ7RbnMgARAgAFAAkJ7RbnMgARAgAAAA==.',
Gl='Glasgoww:BAAALgAECgYJCQABLgAFFAMJCgABAGcPAA==.',
Gn='Gnibat:BAAALgAECgMJBgAAAA==.Gnomerlicous:BAAALgADCgkJCQAAAA==.',
Go='Goburina:BAACLgAFFH8UAAIBAAQJohUgFwDoAAABAAQJohUgFwDoAAAuAAQKfxgAAgEACQlaC1M9AIwBAAEACQlaC1M9AIwBAAAA.Golias:BAAALgADCgEJAQAAAA==.',
Gr='Grenache:BAAALgAECgcJCAAAAA==.Grievo:BAAALgAECgYJCQAAAA==.Grimdawn:BAAALgAFFAEJAQAAAA==.Grimtankdrud:BAAALgADCgcJBwAAAA==.Grinnir:BAAALgAECgIJAwABLgAECgcJGgACACcbAA==.',
Gu='Guildenstern:BAAALgADCgUJBQABLgAFFAMJCgABAGcPAA==.Gulpron:BAAALgAECgYJCAAAAA==.',
Gy='Gypsiey:BAAALgAECgUJBQAAAA==.',
['Gí']='Gímlí:BAACLgAFFH8KAAIFAAMJKBT7XADrAAAFAAMJKBT7XADrAAAuAAQKfzgAAgUACQm8HiQdAHYCAAUACQm8HiQdAHYCAAAA.',
Ha='Halcyndraag:BAABLgAECn9SAAQjAAkJZxUrIQDQAQAjAAcJaxUrIQDQAQAeAAMJwBcBGgCBAAAYAAEJPQJWRAAeAAAAAA==.Handbannana:BAAALgAECgQJBAAAAA==.Handsome:BAAALgAECgcJDAABLgAECgkJGQAPADQJAA==.Happydk:BAACLgAFFH8RAAMGAAQJniCPPgB6AQAGAAQJniCPPgB6AQAbAAMJKRHrLACVAAAuAAQKfygAAwYACQkdI2MXALoCAAYACQlaIWMXALoCABsABwlKGSMnABsBAAAA.Hartu:BAABLgAECn9LAAIiAAkJfxTyDwDpAQAiAAkJfxTyDwDpAQAAAA==.Harukasan:BAAALgADCgIJAgAAAA==.Hashpipe:BAAALgADCgMJAwAAAA==.Hazl:BAAALgAECgMJBAAAAA==.',
He='Healortank:BAAALgAECgEJAQAAAA==.Healsofpain:BAAALgADCgYJBgAAAA==.Healtardo:BAAALgAECgYJCQAAAA==.Hellankeller:BAAALgAECgQJBwAAAA==.Hemic:BAACLgAFFH8RAAIlAAMJMB/PDgD6AAAlAAMJMB/PDgD6AAAuAAQKfzMAAyUACQkjI18FAN0CACUACQkjI18FAN0CAB8ABAnwGhUQACMBAAAA.Hemmorage:BAAALgAECgYJCgABLgAFFAMJBQAGAPUQAA==.Herbalmist:BAAALgAECgUJCwAAAA==.',
Hi='Higag:BAAALgADCgQJBAAAAA==.Hippypally:BAAALgADCgEJAQAAAA==.Hircine:BAAALgAECgQJBQAAAA==.',
Ho='Holysea:BAAALgAECgYJDAABLgAECgkJOgARAGYTAA==.Horatio:BAAALgAECgEJAQABLgAFFAMJCgABAGcPAA==.',
Hr='Hraken:BAAALgAECgUJBgAAAA==.',
Hu='Hukruun:BAAALgADCgEJAgAAAA==.Huntrinei:BAAALgADCgYJCgAAAA==.',
['Hé']='Hélénkéller:BAAALgADCggJDwABLgAFFAMJCAAFABUYAA==.',
Ia='Iahawkeye:BAAALgADCgMJAwAAAA==.',
Ib='Ibhuntin:BAAALgAECggJEgAAAA==.',
Ic='Icyhooves:BAAALgAECgEJAQAAAA==.',
Id='Idiocracy:BAABLgAECn8lAAMiAAkJbhY/DQAWAgAiAAkJrRU/DQAWAgAkAAgJ2w7uMACJAQAAAA==.Idk:BAAALgADCgYJCgAAAA==.',
Ik='Ikodiwa:BAAALgADCgMJAwAAAA==.',
Il='Illigirl:BAAALgADCgEJAQAAAA==.',
Im='Imwithfloki:BAAALgAECgMJBgAAAA==.',
In='Indoti:BAAALgADCgUJBwAAAA==.',
Ir='Ironmark:BAAALgAECgUJCAAAAA==.Irys:BAAALgAECgMJAwAAAA==.',
Is='Isam:BAAALgADCgYJBgAAAA==.Isamidor:BAACLgAFFH8PAAIFAAUJYCIAKABnAQAFAAUJYCIAKABnAQAuAAQKfxwAAgUACQmXI+cEAD8DAAUACQmXI+cEAD8DAAAA.Ismokeu:BAACLgAFFH8WAAMTAAQJpBg0CAANAQATAAQJbxc0CAANAQAJAAMJOgpsGQCfAAAuAAQKfzoAAhMACQmrGZ4NAIwCABMACQmrGZ4NAIwCAAAA.Ismyn:BAAALgAECgEJAgAAAA==.',
It='Itskemba:BAAALgADCgYJBgAAAA==.',
Iy='Iyania:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneal:BAABLgAECn8gAAINAAkJ+wQYpwAtAQANAAkJ+wQYpwAtAQAAAA==.Jalidelo:BAABLgAECn9JAAMJAAkJnh2cCADrAgAJAAkJnh2cCADrAgATAAEJ5gZihgAqAAAAAA==.Jaliwind:BAAALgADCgkJCQAAAA==.Jayan:BAAALgAECgEJAQAAAA==.',
Je='Jenifurr:BAAALgADCgIJAgAAAA==.Jenyx:BAAALgAECgUJCAAAAA==.',
Ji='Jimbowaboki:BAAALgAECgEJAQAAAA==.',
Jo='Johan:BAABLgAECn8eAAIgAAkJMhqFLAAnAgAgAAkJMhqFLAAnAgAAAA==.Jokers:BAABLgAECn8jAAMiAAYJXBUIBQDnAAAkAAUJ4g/8WQDoAAAiAAYJShQIBQDnAAAAAA==.Jokersfists:BAABLgAECn8XAAICAAYJVg8ZEwC4AAACAAYJVg8ZEwC4AAAAAA==.Joranbragi:BAABLgAECn8vAAMNAAcJHQxjGQDGAAANAAYJhwtjGQDGAAAOAAMJjAhhCgBpAAAAAA==.Jordanjr:BAAALgAECggJEQAAAA==.Jormun:BAAALgADCgEJAQAAAA==.Joshy:BAABLgAECn8dAAIcAAYJsRCBDgBJAQAcAAYJsRCBDgBJAQAAAA==.Jotoonice:BAABLgAECn8aAAIhAAgJjBVjYQC9AQAhAAgJjBVjYQC9AQAAAA==.',
Jt='Jtoothaordan:BAACLgAFFH8VAAQmAAYJExf0FAAmAQAmAAQJ3xP0FAAmAQASAAMJsg0uLQBWAAAFAAIJAwgNqwBCAAAuAAQKfy4ABCYACAn9Hw8UAAUCABIACAn9F60gACACACYABgkaJA8UAAUCAAUAAglIIaDPAKsAAAAA.',
Ju='Juglfhednar:BAAALgADCgEJAQAAAA==.Jules:BAAALgAECgUJBQAAAA==.Justbob:BAAALgAECgUJBgAAAA==.',
['Jú']='Júgg:BAAALgAECgQJBgAAAA==.',
Ka='Kaachow:BAABLgAECn8uAAIDAAkJZR+DCQAiAwADAAkJZR+DCQAiAwAAAA==.Kaana:BAABLgAECn9QAAIFAAkJ7xmlHwBpAgAFAAkJ7xmlHwBpAgAAAA==.Kaestey:BAAALgAECggJDQABLgAECgkJIwAhANUXAA==.Kairis:BAAALgAECgYJCQAAAA==.Kallista:BAAALgADCgEJAQAAAA==.Kanoalandiwa:BAAALgAECgEJAQAAAA==.Karthagon:BAABLgAECn8rAAINAAcJUhyIBQDqAQANAAcJUhyIBQDqAQAAAA==.Karungash:BAACLgAFFH8LAAMgAAQJqgoMZAD/AAAgAAQJqgoMZAD/AAAdAAEJVQE+GwA+AAAuAAQKfx0AAyAACAm1Id4QAPMCACAACAm1Id4QAPMCAB0AAgkTEk1SAHcAAAAA.Karva:BAABLgAECn8kAAIQAAkJzBqWBgAqAgAQAAkJzBqWBgAqAgAAAA==.Karvy:BAABLgAECn8kAAIaAAgJXB55AgCoAQAaAAgJXB55AgCoAQABLgAECgkJJAAQAMwaAA==.Kash:BAAALgADCgUJBQABLgAFFAUJEwAEACYlAA==.Kayzer:BAAALgADCgYJGAAAAA==.',
Ke='Kelonaar:BAACLgAFFH8bAAIVAAYJ9x9gCACHAQAVAAYJ9x9gCACHAQAuAAQKfyUAAxUACQlhHqEWADECABUACQlhHqEWADECABkAAgn1Gg45AEoAAAAA.Kelya:BAAALgAECgUJBQABLgAFFAYJGwAVAPcfAA==.Kerrie:BAAALgADCgEJAQAAAA==.',
Kh='Khthonious:BAABLgAECn8VAAICAAcJBx4TOwDbAQACAAcJBx4TOwDbAQAAAA==.',
Ki='Kibblsncrits:BAAALgAECgIJAwABLgAECgkJEgAMAAAAAA==.Kickingdonut:BAACLgAFFH8FAAIKAAMJNx8sHADtAAAKAAMJNx8sHADtAAAuAAQKfywAAwoACAk7IxkJAOcCAAoACAk7IxkJAOcCAAsABgn1GUI3AG4BAAAA.Killerhottie:BAAALgAECgEJAQAAAA==.Killermoomoo:BAAALgAECgQJCgAAAA==.Kinoh:BAAALgADCgkJEAAAAA==.Kittykarma:BAAALgAECgUJBQAAAA==.',
Kl='Kloverr:BAAALgAECgIJAgAAAA==.Klub:BAAALgADCgYJBgAAAA==.',
Ko='Kollita:BAAALgAECgEJAQAAAA==.Komatsu:BAAALgAECgEJAQAAAA==.Kombatkarl:BAAALgADCgMJAwAAAA==.Koramere:BAAALgADCgcJBwAAAA==.',
Kr='Kretaios:BAAALgADCgQJBAAAAA==.Kromir:BAAALgAECgQJBwAAAA==.Kromnar:BAAALgADCgEJAQAAAA==.Kronixrage:BAAALgAECgYJCwAAAA==.Kronn:BAAALgAECgYJBwAAAA==.Krooler:BAAALgAECgQJCAAAAA==.Krum:BAACLgAFFH8gAAINAAUJaR8DKQBnAQANAAUJaR8DKQBnAQAuAAQKfx4AAg0ACAmsHYRRANQBAA0ACAmsHYRRANQBAAAA.',
Ku='Kungfoumoo:BAAALgAECgEJAQAAAA==.',
La='Ladgarkk:BAAALgADCggJFQAAAA==.Lanval:BAABLgAECn9cAAINAAkJgBtIIgB9AgANAAkJgBtIIgB9AgAAAA==.Lardend:BAABLgAECn8WAAIUAAgJ2QcMCADUAAAUAAgJ2QcMCADUAAAAAA==.Laurian:BAAALgADCgcJDwAAAA==.Laurì:BAAALgAECgMJBQABLgAECgkJVQAKABokAA==.',
Le='Leaky:BAAALgAECgIJBAAAAA==.Leetah:BAACLgAFFH8VAAIaAAMJ+R4GBwAGAQAaAAMJ+R4GBwAGAQAuAAQKf3YAAxoACQlkIqYAAMMCABoACQlkIqYAAMMCAAQAAwl9DmszAJEAAAAA.Leftblank:BAAALgAECgcJDQAAAA==.Legitimas:BAAALgAECgEJAQAAAA==.Lemix:BAAALgAECgMJDAAAAA==.',
Li='Liasong:BAAALgADCgMJAwAAAA==.Lilyoptra:BAAALgAECgYJDgABLgAECgYJDwAMAAAAAA==.Lindrael:BAAALgADCgEJAQAAAA==.Liszt:BAAALgAECgYJBgAAAA==.Litallya:BAAALgAECggJDQAAAA==.Littletush:BAAALgAECggJDwAAAA==.Livingdemon:BAAALgAECgUJDwAAAA==.',
Lm='Lminus:BAAALgAECgYJEgAAAA==.',
Lo='Lockolus:BAAALgAECgMJAwAAAA==.Lockpockets:BAAALgADCgEJAQAAAA==.Lootie:BAAALgAECggJDgAAAA==.Loriane:BAAALgAECgUJCAABLgAECgkJKAADAAIgAA==.Lorianth:BAAALgADCgcJDgAAAA==.Lotharbacco:BAAALgAECgMJAwAAAA==.Lovegood:BAAALgADCgEJAQAAAA==.Loveisbeauty:BAAALgAECgUJBwAAAA==.Lowki:BAAALgAECgEJAgAAAA==.',
Ly='Lychi:BAAALgAECgUJCwAAAA==.Lylora:BAACLgAFFH8gAAIDAAQJeCSGBwCmAQADAAQJeCSGBwCmAQAuAAQKf08AAgMACQm8JOIBALoDAAMACQm8JOIBALoDAAAA.Lysera:BAAALgADCgMJAwAAAA==.',
['Lê']='Lêmonaide:BAABLgAECn8tAAMTAAkJTQ+oJgCQAQATAAkJTQ+oJgCQAQAPAAUJAgXEagBzAAAAAA==.',
Ma='Madesh:BAABLgAECn9JAAMQAAkJSBv+BQA8AgAQAAkJtxj+BQA8AgACAAkJSRozKAAqAgAAAA==.Madman:BAABLgAECn8vAAIWAAkJTA9jOQCMAQAWAAkJTA9jOQCMAQAAAA==.Maelle:BAABLgAECn9SAAINAAkJ2iJZDAACAwANAAkJ2iJZDAACAwAAAA==.Magekaestey:BAABLgAECn8jAAIhAAkJ1RfHPAAnAgAhAAkJ1RfHPAAnAgAAAA==.Majandra:BAAALgAECgUJDAAAAA==.Malyndra:BAABLgAECn8yAAMUAAkJaBwEDwA1AgAUAAkJvxoEDwA1AgAQAAYJ9hksDgBvAQAAAA==.Malyssa:BAAALgADCgIJAgAAAA==.Marianne:BAAALgADCgYJBwAAAA==.Marle:BAAALgAECgEJBAAAAA==.Marvolt:BAABLgAECn8YAAIgAAgJcA0RbQBiAQAgAAgJcA0RbQBiAQAAAA==.Masy:BAAALgAECgEJAQAAAA==.',
Mc='Mcrae:BAAALgAECgYJBwAAAA==.',
Md='Md:BAAALgAECgEJAgAAAA==.',
Me='Medrare:BAAALgAECgEJAQAAAA==.Melon:BAAALgADCgEJAQABLgAECgkJDQAMAAAAAA==.Meriam:BAAALgAECgEJAgABLgAFFAMJBQAGAPUQAA==.Merlot:BAAALgAECgEJAQABLgAECgcJCAAMAAAAAA==.Mesmash:BAABLgAECn8wAAIiAAkJniFHBADjAgAiAAkJniFHBADjAgAAAA==.Metadk:BAAALgAECgQJBgABLgAECggJGQAKAGIXAA==.Metahunt:BAAALgAECgIJAgABLgAECggJGQAKAGIXAA==.Metamasters:BAAALgAECgQJBQABLgAECggJGQAKAGIXAA==.Metatotem:BAAALgAECgIJBAABLgAECggJGQAKAGIXAA==.Metavoker:BAAALgAECgEJAQABLgAECggJGQAKAGIXAA==.',
Mi='Mialtaa:BAABLgAECn8vAAILAAkJDxvjCwB2AgALAAkJDxvjCwB2AgAAAA==.Midgiit:BAAALgAECgUJBQABLgAFFAMJBQAGAPUQAA==.Miink:BAAALgADCgYJBgAAAA==.Milkurs:BAAALgAECgQJBwAAAA==.Miniborg:BAABLgAECn8iAAIFAAkJ+xo5HAB7AgAFAAkJ+xo5HAB7AgABLgAFFAUJGQANAHYjAA==.Minidude:BAAALgAECgYJEAAAAA==.Minionghost:BAAALgADCggJCAAAAA==.Miyuki:BAAALgAECgQJBgAAAA==.',
Mj='Mjolnir:BAAALgAECgcJBgAAAA==.',
Mo='Moejojojo:BAABLgAECn8WAAIKAAkJ0yF4DwBTAgAKAAkJ0yF4DwBTAgAAAA==.Monkter:BAABLgAECn8ZAAQKAAgJYheyHADJAQAKAAgJYheyHADJAQAWAAEJ/gbfbgAmAAALAAEJfggUoAAiAAAAAA==.Monsignore:BAAALgADCgQJBAAAAA==.Moofasaha:BAAALgAECgkJEAAAAA==.Mooheals:BAAALgADCgEJAQAAAA==.Moonk:BAAALgAECgcJBQAAAA==.Morduos:BAAALgAECgcJBgABLgAECggJFQACAAceAA==.Morog:BAACLgAFFH8WAAMmAAYJURpxBQC4AQAmAAYJURpxBQC4AQAFAAEJ0w1tqwBCAAAuAAQKfykABBIACQmpGyMsAM0BABIABgmOHSMsAM0BAAUABgkbGq0/ALABACYABgnqE/UpAFEBAAAA.Morragan:BAAALgAECgQJBQAAAA==.Mortegom:BAAALgADCgcJBwAAAA==.Moráthi:BAAALgADCgcJBwAAAA==.',
Mu='Mulvan:BAAALgAECggJEQAAAA==.',
My='Myinja:BAAALgAECgQJCAABLgAECggJGQAKAGIXAA==.Myrddinwyllt:BAAALgAECgYJDAAAAA==.',
Na='Naadra:BAAALgAECgEJAQAAAA==.Nabû:BAAALgADCggJDwAAAA==.Naema:BAAALgAECggJDgAAAA==.Nalid:BAACLgAFFH8TAAIEAAUJJiW2AgCqAQAEAAUJJiW2AgCqAQAuAAQKf0QAAwQACQnAJkAAAIwDAAQACQnAJkAAAIwDAAgAAQmuAl6mABsAAAAA.Nanarus:BAACLgAFFH8NAAITAAIJfRk2JgCOAAATAAIJfRk2JgCOAAAuAAQKf1EAAxMACQmoHiEIAOoCABMACQmoHiEIAOoCAA8ABgnkA+VWALgAAAAA.Nanosec:BAAALgAECgEJAQAAAA==.Nansea:BAAALgAECgEJAgAAAA==.Nashalie:BAABLgAECn80AAIgAAkJsR4pAgB3AgAgAAkJsR4pAgB3AgAAAA==.Natedawg:BAAALgAECgUJCQAAAA==.',
Ne='Neezzdutzz:BAAALgAECgMJAwAAAA==.Nefele:BAABLgAECn8hAAIBAAkJ5RUWIwA8AgABAAkJ5RUWIwA8AgAAAA==.Nepheli:BAACLgAFFH8GAAICAAMJUxefVgDrAAACAAMJUxefVgDrAAAuAAQKf00AAgIACQlrJF4DAFIDAAIACQlrJF4DAFIDAAAA.Newrhu:BAAALgAECgYJBwAAAA==.Nexbasia:BAACLgAFFH8QAAIEAAMJnRLqBADMAAAEAAMJnRLqBADMAAAuAAQKf2YAAwQACQlDH6YAAG8CAAQACQlDH6YAAG8CAAMAAgn2Apr6ABoAAAAA.',
Ni='Nickyboy:BAABLgAECn8lAAQdAAcJyiHhBQAKAgAdAAcJyiHhBQAKAgAgAAIJvg54BwFhAAAcAAEJrBd0PQA3AAAAAA==.Nightevel:BAAALgAECgUJBQAAAA==.Nihimetal:BAAALgAECgUJCAAAAA==.Nikash:BAABLgAECn80AAMIAAkJFBNVHADnAQAIAAkJFBNVHADnAQADAAYJ+QhgfwC8AAAAAA==.Nisato:BAAALgAECgUJBQAAAA==.',
No='Noctum:BAAALgAECgYJEAAAAA==.Nommei:BAAALgAECgcJEwAAAA==.Northic:BAAALgAECgYJBgABLgAECgkJNQAGAPEgAA==.Nortikolait:BAAALgAECgEJAQABLgAECgkJNQAGAPEgAA==.',
Ny='Nyriah:BAAALgAECgUJCwAAAA==.',
Ob='Obm:BAAALgAECgUJCwAAAA==.',
Oc='Octoface:BAAALgAECgYJBQAAAA==.Octt:BAACLgAFFH8HAAIgAAMJoRntagDuAAAgAAMJoRntagDuAAAuAAQKfyAAAiAACQk5HFUFAJoBACAACQk5HFUFAJoBAAAA.',
Of='Offal:BAABLgAECn82AAQiAAYJjxXdAwAlAQAXAAYJCAsJGAA5AQAiAAYJjxXdAwAlAQAkAAEJJQV2swAjAAAAAA==.',
Ol='Olanna:BAAALgAECgYJDAAAAA==.Oldcannabis:BAAALgAECgQJCwAAAA==.',
Om='Ominis:BAAALgAECgUJBgAAAA==.',
Oo='Oomaw:BAAALgAECgMJBAAAAA==.',
Or='Orcal:BAACLgAFFH8gAAIjAAUJ/xj7KQAgAQAjAAUJ/xj7KQAgAQAuAAQKfx0AAiMACAn7GnQQAHECACMACAn7GnQQAHECAAAA.Ormie:BAAALgAECgQJBAAAAA==.Ornimus:BAABLgAECn8eAAQOAAcJUxFsIAAQAQAOAAcJUxFsIAAQAQANAAQJEARkKAGJAAARAAEJgQXgFwAjAAAAAA==.',
Ot='Otherrhu:BAAALgAECgYJCAAAAA==.',
Oz='Ozo:BAABLgAECn8dAAIFAAcJqBIgbQBnAQAFAAcJqBIgbQBnAQAAAA==.',
Pa='Paiva:BAAALgAECgUJCAAAAA==.Palandor:BAAALgADCgMJAwAAAA==.Pallyscorned:BAABLgAECn9FAAIOAAkJ/iHjAgD3AgAOAAkJ/iHjAgD3AgAAAA==.Pampas:BAABLgAECn8bAAMBAAkJkgSndAD/AAABAAkJkgSndAD/AAAVAAEJ5AFvwwAZAAAAAA==.Pandamonic:BAAALgAECgQJBAAAAA==.Paxdei:BAAALgAECgUJCQAAAA==.',
Pe='Ped:BAAALgAECgQJBgAAAA==.',
Ph='Phenixy:BAAALgAECgUJCwAAAA==.Phoebell:BAAALgAECgYJDQAAAA==.',
Pi='Pinkducky:BAABLgAECn8kAAIGAAcJDQbBGgClAAAGAAcJDQbBGgClAAAAAA==.',
Pl='Plen:BAACLgAFFH8FAAIGAAMJ9RCaUQCXAAAGAAMJ9RCaUQCXAAAuAAQKfy8AAxsACQm6H2UCAM0BAAYACQmTHFo1AGECABsABgk/IGUCAM0BAAAA.',
Po='Ponder:BAAALgAECgYJCgAAAA==.Poppyseed:BAAALgAECgMJAwAAAA==.Poquads:BAAALgAECgQJCgAAAA==.',
Pr='Primaris:BAAALgAECgcJDAAAAA==.Prinnce:BAAALgAECgcJDgABLgAECgkJVQAKABokAA==.Príestatute:BAAALgAECgUJBQABLgAFFAMJCgAFACgUAA==.',
Pu='Pulmifinger:BAAALgAECgEJAQAAAA==.Punka:BAAALgAECgEJAQAAAA==.Purplesea:BAAALgADCgcJDQABLgAECgkJOgARAGYTAA==.',
Pv='Pve:BAAALgAECgcJCAAAAA==.',
Qi='Qilt:BAAALgADCgcJBwAAAA==.',
Qu='Quasar:BAABLgAECn8lAAIhAAkJmBgVQQAZAgAhAAkJmBgVQQAZAgAAAA==.',
Ra='Raaluur:BAAALgADCgUJBQAAAA==.Radra:BAABLgAECn9BAAQQAAkJ5BFeAgAiAQAUAAkJfhG4GQCzAQAQAAcJxA1eAgAiAQACAAUJkwlUGQCDAAAAAA==.Raeku:BAABLgAECn8tAAImAAkJkCAUBgDCAgAmAAkJkCAUBgDCAgAAAA==.Rainee:BAAALgADCgYJBwAAAA==.Raja:BAAALgAECgUJDwAAAA==.Rathalo:BAAALgAECgQJBgAAAA==.Rav:BAAALgADCgUJBQAAAA==.Ravick:BAAALgADCgEJAQAAAA==.Razensetral:BAAALgAECggJCAAAAA==.Razzlor:BAAALgADCgUJBQAAAA==.',
Re='Reducto:BAABLgAECn8hAAMQAAYJhRXmFwDiAAACAAYJnBNxfgAjAQAQAAUJPxXmFwDiAAAAAA==.Reenailinefh:BAAALgADCgcJDgAAAA==.Relitha:BAAALgADCgUJCQAAAA==.Remeii:BAABLgAECn8iAAMBAAgJJghPgADgAAABAAcJtgRPgADgAAAVAAYJUQP9cQCVAAAAAA==.Retribution:BAABLgAECn85AAINAAkJ5hM9SADtAQANAAkJ5hM9SADtAQAAAA==.Reylexgt:BAAALgAECgEJAQAAAA==.',
Rh='Rhaenera:BAAALgAECgMJCgABLgAECgkJVQAKABokAA==.Rhage:BAAALgADCgkJCQAAAA==.',
Ri='Richcraniums:BAAALgADCgcJBwAAAA==.',
Ro='Roachers:BAAALgADCgIJAgAAAA==.Robomurph:BAAALgADCggJDwAAAA==.Rolas:BAAALgAECgYJAgAAAA==.Ronfax:BAACLgAFFH8sAAMBAAcJHSLWAADDAgABAAcJHSLWAADDAgAVAAIJxAWMUwBGAAAuAAQKfywAAwEACQm2IzwFAF8DAAEACQm2IzwFAF8DABUABgmeHN8qAJwBAAAA.Ronia:BAAALgADCgIJAgABLgAECgcJGgACACcbAA==.Rooss:BAAALgAECgcJEgAAAA==.Roqane:BAAALgAECgQJBAAAAA==.Roserade:BAAALgAECgkJEwAAAA==.Rothkin:BAAALgADCgMJAwAAAA==.Rotreiter:BAAALgADCgEJAQAAAA==.Rowdyredneck:BAAALgADCgMJAwABLgAECggJGQAKAGIXAA==.',
Ru='Rukea:BAAALgADCgkJCQAAAA==.Rul:BAAALgAFFAEJAQABLgAFFAQJEQAGAJ4gAA==.',
Ry='Ryllae:BAAALgAECgQJBQABLgAECgkJHgAUAFciAA==.Ryuusythe:BAAALgADCgcJBwAAAA==.Ryân:BAAALgADCgEJAQAAAA==.',
['Rì']='Rììdìì:BAAALgAFFAIJAgABLgAFFAMJCgAFACgUAA==.',
Sa='Saara:BAAALgADCgEJAQAAAA==.Sackhammer:BAAALgAECgQJBAAAAA==.Saint:BAAALgAECgkJDwAAAA==.Salopard:BAAALgAECgIJAgAAAA==.Samson:BAABLgAECn8XAAQKAAcJKxzRIgCaAQAKAAYJLRzRIgCaAQALAAUJtxHfTgDFAAAWAAIJ3wpgqgBJAAABLgAECgUJCwAMAAAAAA==.Sanivan:BAABLgAECn8VAAIUAAcJ+hdxGgDvAQAUAAcJ+hdxGgDvAQAAAA==.Sanoan:BAAALgAECgQJBQAAAA==.Saori:BAAALgAECgEJAQAAAA==.Sappy:BAABLgAECn8aAAQfAAcJdR9BCQCuAQAfAAYJsh5BCQCuAQAlAAQJrxwzOwA/AQAnAAQJ8BLcCQDFAAABLgAFFAQJEQAGAJ4gAA==.Sarinae:BAABLgAECn8qAAQjAAkJeAe1CAC5AAAjAAgJzwW1CAC5AAAeAAEJGQ7pBgAsAAAYAAEJwAEQRAAfAAAAAA==.Sarmuc:BAABLgAECn8ZAAMZAAgJmw+8FwBMAQAZAAgJmw+8FwBMAQAVAAEJXwuesAAoAAAAAA==.Sarnluz:BAAALgAECgEJAQABLgAECggJEQAMAAAAAA==.Saryda:BAAALgAECgUJDQABLgAECgcJCAAMAAAAAA==.Sauda:BAAALgAECgEJAQAAAA==.Saurian:BAAALgADCgEJAQAAAA==.',
Sc='Schadoww:BAAALgAECggJDQABLgAFFAMJBQAGAPUQAA==.Scubagal:BAAALgAECgYJDQAAAA==.Scy:BAAALgAECggJDQAAAA==.Scythraza:BAABLgAECn86AAMjAAgJFhuXAQDrAQAjAAgJFhuXAQDrAQAYAAEJCQR9PgAqAAAAAA==.',
Se='Seablue:BAAALgAECgMJBQABLgAECgkJOgARAGYTAA==.Sedaleice:BAAALgAECgEJAQAAAA==.Sedge:BAAALgADCgEJAQAAAA==.Seedsprayer:BAAALgAECgYJDAAAAA==.Selara:BAAALgAECgMJAwAAAA==.Sellenah:BAABLgAECn8aAAICAAcJJxvOXAByAQACAAcJJxvOXAByAQAAAA==.Sensu:BAAALgAECgcJEQAAAA==.Sensual:BAAALgAECgYJAwAAAA==.Sernian:BAAALgAFFAMJBAABLgAFFAUJHwANAPgjAA==.Seä:BAABLgAECn86AAIRAAkJZhMXHAAjAgARAAkJZhMXHAAjAgAAAA==.',
Sh='Shadoweave:BAABLgAECn8dAAIPAAkJqwfcMwBJAQAPAAkJqwfcMwBJAQAAAA==.Shampooshady:BAAALgAECgMJBAAAAA==.Shamtea:BAABLgAECn82AAIVAAkJJhRFBAB7AQAVAAkJJhRFBAB7AQAAAA==.Shandrin:BAAALgAECgEJAQAAAA==.Shapzan:BAABLgAECn8XAAMIAAcJ4hUhLwBjAQAIAAcJ4hUhLwBjAQAaAAUJ3g0YCgCkAAAAAA==.Shareliss:BAAALgADCgYJBgAAAA==.Sharks:BAAALgAECgQJDwAAAA==.Shiik:BAAALgAECgYJBwABLgAECgcJGQARABIYAA==.Shivant:BAABLgAECn86AAMBAAkJSR2tFQCdAgABAAkJSR2tFQCdAgAVAAIJQwWemwBBAAAAAA==.Shmeegleroop:BAAALgAECgYJDgAAAA==.Shroomhunter:BAAALgAECgEJAQAAAA==.Shîvå:BAACLgAFFH8GAAIQAAMJ6SE+AgAQAQAQAAMJ6SE+AgAQAQAuAAQKfzEAAhAACQniID0CAOQCABAACQniID0CAOQCAAAA.',
Si='Sideburns:BAAALgAECgMJAwAAAA==.Silvertime:BAAALgADCgYJBwAAAA==.Sindice:BAAALgAECgYJCwABLgAFFAcJLAABAB0iAA==.',
Sk='Skaa:BAAALgAECgEJAwAAAA==.',
Sl='Slammy:BAAALgAECgQJBAAAAA==.Slanesh:BAAALgAECgIJAgAAAA==.Slimpooshady:BAACLgAFFH8JAAIaAAMJvQymEACHAAAaAAMJvQymEACHAAAuAAQKfzQAAwMACQkWEn0oAA4CAAMACQkWEn0oAA4CABoACQmmEzcRANgBAAAA.Sloth:BAABLgAECn82AAIbAAkJICHHAADWAgAbAAkJICHHAADWAgAAAA==.',
So='Solaspirus:BAABLgAECn8uAAMCAAkJ6BsEJAA/AgACAAkJ6BsEJAA/AgAQAAEJawxCNwAqAAAAAA==.Solinius:BAAALgAECgQJBQAAAA==.Sope:BAAALgAECgYJDQABLgAECggJDgAMAAAAAA==.Sorhtx:BAAALgAECgUJBwAAAA==.Sostoned:BAAALgAECgEJAQABLgAECgkJNAAfAP0cAA==.Soulomatic:BAAALgADCgcJBwAAAA==.',
Sp='Spectors:BAABLgAECn9GAAMcAAgJjBI9AgBLAQAcAAcJHBU9AgBLAQAgAAcJ5wNwwQDKAAAAAA==.Spekturx:BAAALgAECgEJAQAAAA==.Spideygirl:BAABLgAECn8WAAIRAAgJPxzPEQCFAgARAAgJPxzPEQCFAgAAAA==.Sprayinnseed:BAAALgAECgMJBAAAAA==.Sprayinseed:BAAALgADCgMJAwAAAA==.',
Sq='Squarepants:BAAALgAECgQJCQABLgAECgQJDwAMAAAAAA==.',
St='Stabon:BAABLgAECn8lAAIlAAkJcwlDHwCcAQAlAAkJcwlDHwCcAQAAAA==.Stalaediir:BAAALgADCgQJBAAAAA==.Stardre:BAAALgADCgQJBQAAAA==.Stevesmith:BAAALgAECgEJAgAAAA==.Stonedrage:BAAALgADCgEJAQAAAA==.Stormspirits:BAAALgADCgUJBQAAAA==.Sturdyy:BAAALgADCgMJAwAAAA==.Stãrkïllér:BAAALgADCgMJAwAAAA==.',
Su='Sugarmarks:BAAALgAECgYJDwAAAA==.',
Sw='Sweetstorm:BAABLgAECn9fAAIUAAkJFQw6BQAvAQAUAAkJFQw6BQAvAQAAAA==.',
Sy='Synvara:BAAALgADCgUJBQAAAA==.',
['Sê']='Sêphiroth:BAABLgAECn83AAIRAAkJWxeEFABqAgARAAkJWxeEFABqAgAAAA==.',
Ta='Taekoad:BAAALgADCgIJAgAAAA==.Tahlia:BAAALgAECgEJAQAAAA==.Tania:BAABLgAECn8aAAINAAgJsxMTXwCzAQANAAgJsxMTXwCzAQAAAA==.Taredelaria:BAAALgAECgEJAgAAAA==.Tarixx:BAABLgAFFH8GAAMNAAMJ/w5hJACjAAANAAIJQg5hJACjAAAOAAEJeRA0GgAqAAAAAA==.Tazanoth:BAACLgAFFH8IAAQFAAMJBBLAcQC8AAAFAAMJ0Q/AcQC8AAAmAAIJKQ7lKwCDAAASAAEJTArEJgBPAAAuAAQKfyEAAyYACQmaG4kPADYCACYACQmQGokPADYCABIABglBGtYwALABAAAA.',
Te='Teasa:BAACLgAFFH8GAAIFAAIJmA09PACVAAAFAAIJmA09PACVAAAuAAQKf0IAAgUACQnZGYohAF8CAAUACQnZGYohAF8CAAAA.Tekeelà:BAACLgAFFH8SAAQFAAYJixlDAgB7AQAFAAYJixlDAgB7AQASAAEJVgAiLgA1AAAmAAEJhAF0OAAqAAAuAAQKfzIABAUACQl2IaMVAIoCAAUACQkHH6MVAIoCACYACQm6GJ8PADUCABIABwm3EeY5AHoBAAAA.Tekkamaki:BAAALgADCgcJCAAAAA==.',
Th='Thalion:BAABLgAECn8cAAMFAAYJdwOZwwDAAAAFAAYJdwOZwwDAAAAmAAUJcgF+VQBXAAAAAA==.Theenna:BAAALgAECgYJDgAAAA==.Thetodd:BAAALgAECgIJAgAAAA==.Thianna:BAABLgAECn8pAAMRAAkJyBn5GwAkAgARAAkJyBn5GwAkAgANAAgJdRJFFQDmAAAAAA==.Thiculuskage:BAABLgAECn8YAAIRAAkJvB77BwAMAwARAAkJvB77BwAMAwAAAA==.Thinkso:BAAALgADCgcJGwAAAA==.Thobu:BAAALgAECgcJCwAAAA==.Thodos:BAAALgADCgEJAQAAAA==.Thornscale:BAABLgAECn9OAAQjAAkJ3ho3EQBcAgAjAAkJ3ho3EQBcAgAYAAYJogvrKAAsAQAeAAYJbhaDAQArAQAAAA==.Thorrent:BAAALgADCgcJDQAAAA==.',
Ti='Tigolcrittys:BAAALgAECgcJEgABLgAFFAMJCgAFACgUAA==.Timeforloads:BAABLgAECn8rAAMIAAkJ8hYdNABIAQAIAAcJOhUdNABIAQADAAYJxB/5BQA6AQAAAA==.Tirria:BAAALgAECgQJBQAAAA==.',
To='Tolk:BAAALgAECgcJEQAAAA==.Tomzombe:BAAALgAECgQJBgAAAA==.Totem:BAABLgAECn8WAAIVAAgJvQu3RQAdAQAVAAgJvQu3RQAdAQAAAA==.Totenz:BAAALgADCgYJBgAAAA==.',
Tr='Traveler:BAAALgAECgIJAgAAAA==.Trickyflamom:BAABLgAECn8aAAIhAAcJzBzLBgC4AQAhAAcJzBzLBgC4AQABLgAFFAQJIgAhAPYaAA==.Troloq:BAABLgAECn85AAQcAAkJfx2BCADgAQAgAAgJHhuKNwD7AQAcAAgJWReBCADgAQAdAAYJTRoEFAAQAQAAAA==.Trondoom:BAAALgADCgYJBgAAAA==.',
Tu='Tugboattimmy:BAAALgAECgEJAQAAAA==.Tulisha:BAAALgAECgUJCgAAAA==.Turero:BAABLgAECn8WAAIRAAcJkAeiBwDsAAARAAcJkAeiBwDsAAABLgAFFAQJGAADAEIRAA==.Turger:BAAALgAECgUJCAABLgAECgkJEAAMAAAAAA==.Turinnii:BAAALgADCgcJBwAAAA==.',
Ul='Uller:BAABLgAECn8oAAIhAAkJDhrQMABWAgAhAAkJDhrQMABWAgAAAA==.',
Um='Umbrafang:BAAALgAECgEJBAAAAA==.',
Un='Unholyspirit:BAAALgAECgQJDwAAAA==.',
Va='Vahlorraa:BAABLgAECn8nAAMRAAcJaxCrBQAsAQARAAYJ6RGrBQAsAQANAAEJdANPVwAUAAAAAA==.Vaimei:BAACLgAFFH8GAAIgAAMJQBU0JwDNAAAgAAMJQBU0JwDNAAAuAAQKfzcAAx0ACQn4Ii8CAKICAB0ACAk9Iy8CAKICACAACAkDID8WAJ8CAAAA.Valashune:BAAALgADCgEJAQAAAA==.Valsilla:BAAALgAECgYJBgABLgAECgkJHgAUAFciAA==.Vapor:BAABLgAECn80AAIfAAkJ/RxSAABrAgAfAAkJ/RxSAABrAgAAAA==.Varaine:BAAALgAECgIJAgAAAA==.Varanius:BAAALgAECgEJAgAAAA==.',
Ve='Veebes:BAAALgAECggJCAAAAA==.Veebs:BAABLgAECn8dAAMkAAgJqhNcCAAHAQAkAAgJqhNcCAAHAQAiAAEJAAAySAAuAAAAAA==.Velóran:BAAALgADCgcJBwAAAA==.Vendola:BAABLgAECn8gAAIhAAgJaQboqgAqAQAhAAgJaQboqgAqAQAAAA==.Vento:BAABLgAECn8VAAIGAAgJjxWuYgCjAQAGAAgJjxWuYgCjAQAAAA==.Verité:BAABLgAECn8UAAMeAAgJ8gwzDwAXAQAeAAcJdg4zDwAXAQAjAAcJfQmBTgD0AAAAAA==.Veterpeinss:BAAALgADCggJDgAAAA==.',
Vi='Viento:BAAALgADCgcJBwAAAA==.Villiveil:BAAALgAECgEJAQABLgAFFAQJBgANAJoZAA==.Vintersorg:BAAALgAECgUJCQAAAA==.Virauca:BAABLgAECn9MAAICAAkJjhYtLgAOAgACAAkJjhYtLgAOAgAAAA==.Viuhl:BAAALgADCgQJAwAAAA==.',
Vo='Vodgrax:BAAALgAECgIJAgAAAA==.Voidstar:BAAALgAECgUJDAAAAA==.Voltimand:BAAALgAECgEJAQABLgAFFAMJCgABAGcPAA==.',
Vv='Vvicked:BAABLgAECn8gAAIGAAgJrCI8FwC7AgAGAAgJrCI8FwC7AgAAAA==.',
Vy='Vynesta:BAABLgAECn8eAAIUAAkJVyKvAwAZAwAUAAkJVyKvAwAZAwAAAA==.',
Wa='Wala:BAAALgAECgcJDAAAAA==.Wamoo:BAAALgAECgEJAgAAAA==.Wanagi:BAAALgAECgUJBQAAAA==.Wankz:BAAALgAECgkJEgAAAA==.Wankzerkin:BAAALgADCgEJAQAAAA==.Warriorguyes:BAABLgAECn8fAAIkAAkJtSKbBwDlAgAkAAkJtSKbBwDlAgAAAA==.',
We='Weyna:BAABLgAECn84AAMWAAgJ3hHVMgCsAQAWAAgJ3hHVMgCsAQALAAYJVAmnTQDJAAABLgAFFAYJHwAYAO8UAA==.',
Wh='Whisperingei:BAAALgAECgYJCgAAAA==.Whomper:BAAALgAECgYJEAAAAA==.Whpheonix:BAAALgADCgkJEAAAAA==.',
Wi='Widowx:BAACLgAFFH8JAAMVAAMJaw+pFwC2AAAVAAMJaw+pFwC2AAABAAEJEgEjjwAgAAAuAAQKfzQAAhUACQnIHKwCAN8BABUACQnIHKwCAN8BAAAA.Winfurdal:BAAALgADCggJCAAAAA==.',
Wo='Womphunt:BAABLgAECn8WAAIFAAcJlBqgPgDnAQAFAAcJlBqgPgDnAQABLgAECgkJLAATABkhAA==.',
Wr='Wrandohunt:BAAALgAECgEJBAAAAA==.Wrandowdemon:BAAALgADCgcJBwAAAA==.Wreckitrandy:BAAALgAECgEJAQAAAA==.Wryn:BAAALgAECgkJEQABLgAFFAMJBQAGAPUQAA==.',
Wu='Wulyn:BAAALgAECgcJDAAAAA==.',
Wy='Wylla:BAABLgAECn8XAAIKAAYJ/A+WBQAFAQAKAAYJ/A+WBQAFAQAAAA==.',
Xa='Xalethra:BAABLgAECn89AAICAAkJ8CQ7BQA0AwACAAkJ8CQ7BQA0AwAAAA==.Xaltheris:BAAALgAECgUJBgAAAA==.',
Xe='Xelha:BAAALgAECgYJBgAAAA==.Xenophobias:BAABLgAECn8YAAMbAAcJuxBSBgDaAAAbAAYJahNSBgDaAAAGAAIJUgMdowEdAAAAAA==.',
Xh='Xhosen:BAABLgAFFH8HAAIGAAIJEhIyVwCLAAAGAAIJEhIyVwCLAAAAAA==.',
Xr='Xratedmurdaa:BAAALgAECgEJAQAAAA==.',
Xs='Xsuns:BAABLgAECn9JAAIDAAkJYxqqHQBZAgADAAkJYxqqHQBZAgAAAA==.',
Ya='Yarloon:BAAALgADCgcJBwAAAA==.',
Yt='Ytsirk:BAAALgADCgYJBgAAAA==.',
Yv='Yve:BAAALgAECgUJDQAAAA==.',
Za='Zaharian:BAAALgAECgEJAQAAAA==.Zalajin:BAAALgAECgUJCQAAAA==.Zalila:BAAALgADCgYJBgAAAA==.Zanasi:BAEALgAECgcJBwABLgAFFAQJFAAFABQiAA==.Zarayndia:BAAALgAECgYJCAAAAA==.',
Ze='Zeddicus:BAABLgAECn8tAAMcAAkJ9wi2DgBwAQAcAAkJfAi2DgBwAQAgAAUJDgXk8gB8AAAAAA==.Zendragan:BAACLgAFFH8HAAIWAAMJzxAbQQCfAAAWAAMJzxAbQQCfAAAuAAQKfx4AAhYACQlOGOcXAFkCABYACQlOGOcXAFkCAAAA.Zerhas:BAAALgAECgEJAwAAAA==.',
Zo='Zoe:BAAALgAECgQJCQAAAA==.Zoidz:BAAALgAECggJDAAAAA==.Zombiemagic:BAAALgADCgMJAwAAAA==.Zombruh:BAAALgAECgEJAQAAAA==.Zomgimlothar:BAAALgADCgIJAwAAAA==.Zoomy:BAAALgAECgQJCwAAAA==.',
Zy='Zyntarum:BAAALgADCgEJAQAAAA==.Zythopoios:BAAALgAFFAEJAgAAAA==.',
Zz='Zzilladi:BAABLgAFFH8SAAMTAAYJ1RkTCQC8AQATAAYJ1RkTCQC8AQAPAAEJAACzRAAAAAAAAA==.Zzilladinzz:BAACLgAFFH8UAAINAAUJjSBuMQBOAQANAAUJjSBuMQBOAQAuAAQKfyIAAg0ACQkIIwsSAAIDAA0ACQkIIwsSAAIDAAAA.',
['Ëu']='Ëulogy:BAAALgAECgcJEQABLgAFFAMJBgAQAOkhAA==.',
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
