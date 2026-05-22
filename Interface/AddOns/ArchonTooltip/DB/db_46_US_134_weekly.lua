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

local lookup = {'DeathKnight-Unholy','DemonHunter-Devourer','Paladin-Protection','Druid-Guardian','Hunter-BeastMastery','Unknown-Unknown','Mage-Frost','Paladin-Retribution','Monk-Brewmaster','Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Shaman-Elemental','Warrior-Arms','Priest-Holy','DemonHunter-Havoc','Druid-Restoration','Druid-Balance','Warlock-Affliction','Monk-Mistweaver','Warrior-Protection','DemonHunter-Vengeance','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Druid-Feral','Hunter-Marksmanship','Priest-Shadow','DeathKnight-Blood','Shaman-Restoration','Rogue-Subtlety','Priest-Discipline','Monk-Windwalker','Rogue-Assassination','Hunter-Survival','DeathKnight-Frost','Rogue-Outlaw','Shaman-Enhancement','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Kilrogg',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aazr:BAAALgADCgQJBAAAAA==.',
Ab='Abartheris:BAABLgAECn8dAAIBAAYJTwU0qwDMAAABAAYJTwU0qwDMAAAAAA==.Abroghast:BAAALgAECgUJBQAAAA==.',
Ac='Acanoffood:BAABLgAECn8pAAICAAkJgRMZKwDTAQACAAkJgRMZKwDTAQAAAA==.',
Ad='Adel:BAAALgAECgMJAwAAAA==.Adelil:BAAALgADCgEJAwAAAA==.Ademai:BAAALgADCgIJAgAAAA==.Adeptus:BAABLgAECn8VAAIDAAYJ5Q36IgDwAAADAAYJ5Q36IgDwAAAAAA==.',
Ae='Aemeath:BAACLgAFFH8HAAICAAQJeA5xNQADAQACAAQJeA5xNQADAQAuAAQKfxwAAgIACAkXHDY6AAsCAAIACAkXHDY6AAsCAAAA.Aendres:BAAALgAECgYJDwAAAA==.Aethalyn:BAAALgAECggJCAAAAA==.',
Af='Afitis:BAAALgADCgIJAgAAAA==.',
Ag='Agriopas:BAABLgAECn8hAAIEAAYJygqOJQCiAAAEAAYJygqOJQCiAAABLgAECgcJGgAFAJoJAA==.',
Ah='Aharon:BAAALgADCgkJCgAAAA==.',
Ai='Aireas:BAAALgAECggJCwAAAA==.Aizen:BAAALgADCgYJBgABLgAECgYJCAAGAAAAAA==.',
Al='Alassomorph:BAAALgAECgYJDwAAAA==.Alazaie:BAAALgADCgMJAwAAAA==.Albus:BAACLgAFFH8MAAIHAAQJfBfYUQABAQAHAAQJfBfYUQABAQAuAAQKfygAAgcACQkvIH0RALwCAAcACQkvIH0RALwCAAAA.Aldasar:BAAALgADCgUJBQAAAA==.Allayna:BAABLgAECn83AAIIAAkJdSE7CQDrAgAIAAkJdSE7CQDrAgAAAA==.Alline:BAAALgAECgkJCQAAAA==.Almitvez:BAAALgADCgcJBwABLgAECgYJFAAJAJQeAA==.Aloha:BAACLgAFFH8FAAIKAAIJHBoYJwCYAAAKAAIJHBoYJwCYAAAuAAQKfxsAAgoACAnLE44hAKwBAAoACAnLE44hAKwBAAAA.Alohacuzz:BAAALgAECgEJAgAAAA==.Alysaliu:BAACLgAFFH8LAAILAAQJxRvnLwAwAQALAAQJxRvnLwAwAQAuAAQKfzUAAwsACQktJA4FABUDAAsACQktJA4FABUDAAwABAnBFXkrABIBAAAA.Alysen:BAAALgAECgQJCgABLgAECgYJHQANAC8jAA==.',
Am='Amisan:BAAALgADCgEJAQAAAA==.Amishpaladin:BAAALgAFFAMJBAAAAA==.Amishwarlock:BAAALgAECgYJCQABLgAFFAMJBAAGAAAAAA==.Amonotep:BAAALgAECgQJAwAAAA==.Amorianar:BAAALgADCgMJAwABLgAECgkJEwAGAAAAAA==.Amory:BAAALgAECgYJCQABLgADCgkJGQAGAAAAAA==.',
An='Anchor:BAABLgAECn8XAAIOAAYJfAbPUgD7AAAOAAYJfAbPUgD7AAAAAA==.Andja:BAABLgAECn85AAIPAAkJzSWjAABRAwAPAAkJzSWjAABRAwAAAA==.Andromedae:BAABLgAECn8cAAIQAAkJoBANGADDAQAQAAkJoBANGADDAQAAAA==.Anexa:BAAALgAECgYJDwAAAA==.Angela:BAAALgAECgMJBgAAAA==.Anurek:BAAALgAECgEJAQAAAA==.',
Ar='Argulas:BAAALgADCgkJFQAAAA==.Ariajade:BAAALgAECgEJAQAAAA==.Ark:BAAALgAECgYJEgAAAA==.Arn:BAAALgAECgQJCQABLgAECgcJEgAGAAAAAA==.Arthrex:BAAALgAECgYJDAAAAA==.Arthus:BAAALgAECgYJDAAAAA==.Arturias:BAAALgAECgQJCwABLgAECgkJOQARAMoiAA==.',
As='Ashant:BAAALgADCgUJBQAAAA==.Asmobob:BAABLgAECn8hAAIRAAcJfBrADwDFAQARAAcJfBrADwDFAQAAAA==.',
Au='Augmentin:BAABLgAECn8fAAMSAAgJSBzZFgBJAgASAAcJCx/ZFgBJAgATAAgJUg9oLAAYAQAAAA==.Auntfranny:BAAALgADCgEJAQAAAA==.Autoshot:BAAALgAECgUJBQAAAA==.',
Av='Avanie:BAAALgADCgYJBgAAAA==.Avina:BAAALgAECgQJCAAAAA==.Avrami:BAAALgADCgkJCgAAAA==.',
Aw='Aw:BAABLgAECn8uAAQLAAgJkSETGQBUAgALAAYJXSMTGQBUAgAMAAUJFhZyJAA3AQAUAAIJyhYuIQBHAAAAAA==.Awokenbigdam:BAAALgAECgEJAQAAAA==.',
Ba='Babycoffee:BAAALgAECgkJDgAAAA==.Bahamutz:BAAALgADCgUJBAAAAA==.Bahwee:BAAALgAECgYJDwAAAA==.Bamboodragon:BAAALgAECgEJAQAAAA==.Bangbangdou:BAABLgAECn8cAAIKAAgJtBs8EABNAgAKAAgJtBs8EABNAgAAAA==.Banzjo:BAAALgAECgEJAQAAAA==.Bastor:BAAALgADCgIJAgAAAA==.Bayle:BAAALgAECgUJCgAAAA==.',
Be='Bearnekkid:BAAALgAECgEJAQABLgAECgQJBgAGAAAAAA==.Bearsgomoo:BAAALgAECgQJBAABLgAECggJKQABACIiAA==.Beef:BAAALgAECgEJAQABLgAECgQJBQAGAAAAAA==.Beerthrowguy:BAABLgAECn8bAAMJAAkJ0yGpAgAEAwAJAAkJ0yGpAgAEAwAVAAcJJhw6EwAVAgAAAA==.Bellaofroses:BAAALgADCgcJDAAAAA==.Bellatrix:BAAALgADCgYJBgAAAA==.Beneb:BAAALgAECgYJCwAAAA==.Benebeorn:BAACLgAFFH8MAAICAAQJFRh9HwBKAQACAAQJFRh9HwBKAQAuAAQKfx4AAgIACQnuILUaALMCAAIACQnuILUaALMCAAAA.Benkinobi:BAAALgAECgQJCwAAAA==.',
Bh='Bhaer:BAAALgAECgEJAgAAAA==.',
Bi='Bichewich:BAAALgADCgYJBgAAAA==.Bigal:BAAALgAECgMJAwABLgAECgkJDgAGAAAAAA==.Bigshot:BAAALgADCgYJCQAAAA==.Billyjoe:BAAALgAECgMJBQAAAA==.Binti:BAAALgADCgMJAwAAAA==.Bittronoxus:BAABLgAECn8lAAIHAAgJ2BKAUACoAQAHAAgJ2BKAUACoAQAAAA==.',
Bl='Blackryder:BAAALgAECgUJDgAAAA==.Bleys:BAAALgAECgQJBwABLgAECgkJMgAIAMIdAA==.Bloge:BAAALgAECgEJAQAAAA==.',
Bo='Bobbysmerica:BAABLgAECn8pAAMWAAgJuCEABQCKAgAWAAgJuCEABQCKAgAPAAEJ9At+QgA0AAAAAA==.Bobocanfly:BAABLgAECn8cAAMXAAgJoRWFCQB9AQAXAAgJoRWFCQB9AQARAAEJAAAPdAAxAAAAAA==.Bodikhan:BAAALgAECgUJCgAAAA==.',
Br='Braxte:BAABLgAECn8uAAMNAAkJdR1nFwCRAgANAAgJOR5nFwCRAgAPAAUJmxRKFwBFAQAAAA==.Breecy:BAAALgAECgUJCgAAAA==.Briguydkguy:BAACLgAFFH8KAAIBAAQJkQvOSgAhAQABAAQJkQvOSgAhAQAuAAQKfxgAAgEACAmfFuhgANEBAAEACAmfFuhgANEBAAAA.Brisstle:BAAALgAECgIJAgAAAA==.Britziola:BAAALgAECgYJDgABLgADCgkJGQAGAAAAAA==.Brokenvoid:BAABLgAECn8eAAICAAcJzBpGPwB+AQACAAcJzBpGPwB+AQAAAA==.Bruiser:BAABLgAFFH8FAAMPAAMJMQaZFQC2AAAPAAMJMQaZFQC2AAANAAEJRQBWPAAhAAAAAA==.Brusalt:BAAALgADCggJCAAAAA==.Brusten:BAAALgAECgkJCwABLgAECgkJLgANAHUdAA==.Bryce:BAAALgAECgUJEAAAAA==.',
Bu='Buggies:BAACLgAFFH8RAAIHAAQJ1CBCIQB7AQAHAAQJ1CBCIQB7AQAuAAQKfzQAAgcACQmpJX4SADgDAAcACQmpJX4SADgDAAAA.Buggs:BAAALgAECgMJBAABLgAFFAQJEQAHANQgAA==.Buldozz:BAABLgAECn8oAAIKAAcJVxbyKAB3AQAKAAcJVxbyKAB3AQAAAA==.Bullit:BAAALgADCgYJCAABLgAECgQJBgAGAAAAAA==.Burnination:BAABLgAECn8oAAIHAAcJByV2GgCCAgAHAAcJByV2GgCCAgAAAA==.Burnzie:BAAALgADCgUJAwAAAA==.Butterfayce:BAABLgAECn83AAMKAAkJGCGYAgBPAwAKAAkJGCGYAgBPAwAIAAYJ7w5XkAAGAQAAAA==.',
By='Bycew:BAAALgAECgUJDAABLgAECgUJEAAGAAAAAA==.',
Bz='Bzu:BAAALgAECgcJCwAAAA==.',
Ca='Cadastrasz:BAABLgAECn9KAAQYAAkJJhMCCAAsAgAYAAkJJhMCCAAsAgAZAAkJAQklJwBSAQAaAAMJrAFjOQBOAAAAAA==.Cae:BAAALgADCgkJFQAAAA==.Camachopres:BAAALgAECgUJBQAAAA==.Cameocreme:BAAALgAECgIJAgAAAA==.Captfrost:BAAALgAECgEJAQAAAA==.Carsonkiller:BAAALgADCgEJAQABLgAECggJHgAMACIaAA==.Catalyze:BAAALgAECgQJCAABLgAECgkJJQAZANMNAA==.Cateurize:BAABLgAECn8lAAIZAAkJ0w0xHgCUAQAZAAkJ0w0xHgCUAQAAAA==.',
Ce='Ceenit:BAABLgAECn8nAAIIAAkJpB6LGABxAgAIAAkJpB6LGABxAgAAAA==.Celalaliia:BAAALgADCgMJAwAAAA==.Celawyn:BAAALgAECggJEgAAAA==.',
Ch='Chainedfire:BAAALgAECgQJBwAAAA==.Chasemon:BAABLgAECn8fAAIbAAcJVhwKCADxAQAbAAcJVhwKCADxAQAAAA==.Chaser:BAAALgAECgQJBgABLgAECgcJHwAbAFYcAA==.Chaøtical:BAAALgAECgYJDgAAAA==.Chicosan:BAAALgADCggJDQAAAA==.Chiliconcrne:BAAALgAECgIJAgAAAA==.Chrisolski:BAAALgAECgEJAQABLgAECgUJCgAGAAAAAA==.',
Ci='Cirragos:BAAALgAECgYJEwAAAA==.',
Cl='Clamer:BAAALgADCgcJEAAAAA==.Clawdite:BAAALgADCgYJBgABLgAECgYJFAAJAJQeAA==.Clawesome:BAAALgAECgUJBQAAAA==.Cleansinq:BAAALgAECgEJAgAAAA==.Cloudsmoker:BAABLgAECn8dAAMSAAgJ4g5UPABaAQASAAgJ4g5UPABaAQATAAIJTgfVdQBMAAAAAA==.',
Co='Corien:BAAALgAECgYJEAAAAA==.',
Cr='Crazegrippin:BAAALgAECgIJAwAAAA==.Crimsonmoon:BAABLgAECn8uAAIcAAkJPRCSCACmAQAcAAkJPRCSCACmAQAAAA==.Cryomara:BAAALgADCgYJCgAAAA==.',
Cu='Cueball:BAAALgADCgYJDAAAAA==.',
Cy='Cylasta:BAAALgADCgQJBgAAAA==.Cyndraexa:BAABLgAECn8UAAIdAAYJYwT2PgC8AAAdAAYJYwT2PgC8AAAAAA==.Cynia:BAABLgAECn8VAAIRAAYJogreJQDiAAARAAYJogreJQDiAAAAAA==.Cynra:BAABLgAECn8jAAMSAAkJFBvwDAC0AgASAAkJFBvwDAC0AgATAAEJXRJWZgA1AAAAAA==.Cyrakos:BAAALgADCgEJAQAAAA==.',
['Cõ']='Cõwbell:BAAALgADCgEJAQAAAA==.',
Da='Dalize:BAAALgAECgcJCwAAAA==.Danarrath:BAABLgAECn8UAAIEAAYJCRNmGwDxAAAEAAYJCRNmGwDxAAAAAA==.Danger:BAAALgAECgQJBQAAAA==.Danklins:BAABLgAECn84AAMZAAkJyhsHCwBlAgAZAAkJyhsHCwBlAgAaAAcJTBFyCABgAQAAAA==.Dariabell:BAAALgAECgIJAgAAAA==.Darkramone:BAAALgAECgQJBgAAAA==.Darrow:BAAALgADCgQJBAAAAA==.Darthbane:BAAALgAECgQJCQAAAA==.Darthvada:BAABLgAECn8YAAMBAAcJHRWrWgBuAQABAAcJHRWrWgBuAQAeAAIJgQuTOQBaAAAAAA==.',
De='Deadlydemon:BAAALgADCgEJAQAAAA==.Deadpoint:BAABLgAECn8dAAINAAYJLyOfFwDkAQANAAYJLyOfFwDkAQAAAA==.Deadski:BAABLgAECn8UAAIBAAYJixmZYgBZAQABAAYJixmZYgBZAQAAAA==.Deathfrost:BAACLgAFFH8KAAIHAAQJ0RD/OwBCAQAHAAQJ0RD/OwBCAQAuAAQKfx0AAgcACAmTHfoxAA8CAAcACAmTHfoxAA8CAAAA.Debz:BAAALgADCgkJCQAAAA==.Defeatzhealz:BAAALgAECgYJEwAAAA==.Defeatzhunt:BAABLgAECn8XAAMFAAgJCxnXHABZAgAFAAgJCxnXHABZAgAcAAEJAABunAAJAAAAAA==.Deirdra:BAAALgAECgUJBQABLgAECgkJMgAIAMIdAA==.Delarium:BAAALgAECgEJAQAAAA==.Demonaria:BAABLgAECn85AAMRAAkJyiJPAgADAwARAAkJiSJPAgADAwAXAAUJbSJpCQCAAQAAAA==.Denariah:BAAALgAECgMJAwABLgAECgYJHQAEACocAA==.Dendranaar:BAAALgAECgMJBAAAAA==.Dernen:BAAALgAECgYJDwABLgAECgYJFAAEAAkTAA==.Derpnface:BAAALgAECgYJEwAAAA==.Desecration:BAABLgAECn8uAAICAAcJPyQZGQA9AgACAAcJPyQZGQA9AgAAAA==.Devilhandler:BAAALgADCgcJDgAAAA==.Dezimorikko:BAAALgADCgcJBwAAAA==.',
Di='Dirgir:BAABLgAECn8eAAIeAAkJCyE+BAC2AgAeAAkJCyE+BAC2AgAAAA==.Disk:BAAALgAECgIJAgAAAA==.Distonia:BAABLgAECn8hAAIfAAcJQR5BEgBoAgAfAAcJQR5BEgBoAgAAAA==.',
Do='Dorothy:BAACLgAFFH8HAAIBAAMJownoLgDdAAABAAMJownoLgDdAAAuAAQKfx0AAgEACAkmHRQ/AMABAAEACAkmHRQ/AMABAAAA.',
Dr='Dracheo:BAACLgAFFH8PAAIHAAQJwxKHOQBGAQAHAAQJwxKHOQBGAQAuAAQKfzUAAgcACQlpIegtALoCAAcACQlpIegtALoCAAAA.Dragonbrr:BAAALgAECgUJDAABLgAECgcJGQAKAF8kAA==.Dragonwizard:BAABLgAECn8jAAIHAAcJ9huYaAAFAgAHAAcJ9huYaAAFAgAAAA==.Drakonna:BAAALgAECgMJBgAAAA==.Dranix:BAAALgAECgUJCwAAAA==.Draupaadi:BAAALgADCgYJBgAAAA==.Dreygur:BAAALgAECgUJCQAAAA==.Droiden:BAABLgAECn8VAAIFAAcJDA06YwAiAQAFAAcJDA06YwAiAQAAAA==.Droidetté:BAAALgAECgUJBgAAAA==.Droidén:BAAALgAECgEJAQAAAA==.Drotar:BAABLgAECn8qAAQTAAgJzA52JgA9AQATAAcJOhB2JgA9AQAbAAYJKAUqIQCVAAAEAAEJOQZrTAAWAAAAAA==.Drovak:BAAALgAECgcJEAAAAA==.',
Du='Dumbdog:BAACLgAFFH8NAAISAAQJER8cEgBtAQASAAQJER8cEgBtAQAuAAQKfzMAAxIACQlgJYQDAFoDABIACQlgJYQDAFoDABMABgmaEx0+ADoBAAEuAAUUBwkdABgAZRwA.Dumichauch:BAACLgAFFH8MAAISAAQJMA52IAAFAQASAAQJMA52IAAFAQAuAAQKfzIAAhIACQmTG+4XAHcCABIACQmTG+4XAHcCAAAA.Durin:BAABLgAECn8hAAIIAAcJGBY+VgB+AQAIAAcJGBY+VgB+AQAAAA==.Duzzer:BAAALgADCgEJAQAAAA==.',
['Dé']='Déâth:BAAALgADCgkJCwAAAA==.',
Ec='Echo:BAAALgAECgcJCAAAAA==.',
Eg='Eggars:BAABLgAECn8dAAMLAAcJpAg1eAAMAQALAAcJpAg1eAAMAQAUAAMJEgdRHwBSAAAAAA==.',
Ek='Ekee:BAAALgAECgQJCAAAAA==.',
El='Elegance:BAAALgADCgIJAgAAAA==.Ellý:BAAALgADCgEJAQAAAA==.',
Em='Emberleaf:BAAALgADCgcJDgAAAA==.Emofriz:BAAALgAECgUJCQAAAA==.Emolate:BAABLgAECn8VAAILAAgJagnTXQBHAQALAAgJagnTXQBHAQABLgAFFAcJIwAFANEgAA==.',
En='Ensetrend:BAAALgAECgEJAQAAAA==.Enve:BAABLgAECn8iAAICAAkJVh9LEQB3AgACAAkJVh9LEQB3AgAAAA==.',
Er='Erso:BAAALgADCgcJBwAAAA==.',
Eu='Euforia:BAAALgAECgEJAQAAAA==.',
Ev='Evanorah:BAAALgAECgEJAQAAAA==.Eviltiger:BAABLgAECn84AAMFAAkJiyLtBwDgAgAFAAkJPiHtBwDgAgAcAAkJnRUDBwDVAQAAAA==.',
Ew='Ewik:BAABLgAECn8ZAAMYAAgJYRd7EgAYAgAYAAgJYRd7EgAYAgAaAAMJLQ3FFAB0AAAAAA==.',
Ex='Excalìbur:BAAALgAECgQJBgAAAA==.',
Ey='Eydor:BAAALgADCggJCAAAAA==.',
Fa='Faent:BAABLgAECn8WAAIgAAYJxhLTIAAwAQAgAAYJxhLTIAAwAQAAAA==.Falimonki:BAAALgAECgMJAwAAAA==.Falinora:BAACLgAFFH8MAAMKAAMJGxg5IADPAAAKAAMJGxg5IADPAAAIAAEJrw40cQBPAAAuAAQKfzQAAwoACQnFGqMiAAoCAAoACAltGaMiAAoCAAgACQnaF/RWAHwBAAAA.Famous:BAAALgAECgMJAwAAAA==.Fantasticfox:BAABLgAECn88AAMLAAkJBxNoLwDcAQALAAkJBxNoLwDcAQAMAAQJSQpFMgDvAAAAAA==.',
Fe='Felbyte:BAAALgADCgMJAwAAAA==.Felixs:BAABLgAECn8TAAIUAAYJZRqoCQBZAQAUAAYJZRqoCQBZAQAAAA==.Fellhanded:BAAALgADCgcJBwAAAA==.Feloron:BAAALgAECgQJCgAAAA==.Feluria:BAAALgADCgYJBgAAAA==.Feodin:BAACLgAFFH8HAAIIAAQJKRHiIwA9AQAIAAQJKRHiIwA9AQAuAAQKfxgAAwgACQkQGy0uAP8BAAgACQkQGy0uAP8BAAMABQlADJckAJwAAAAA.Feosdragon:BAAALgADCgYJBgAAAA==.Feraldank:BAAALgAECgIJAgAAAA==.Ferrovax:BAAALgADCgEJAQABLgAECggJGgACADYcAA==.',
Fi='Fistariir:BAAALgAFFAMJAwABLgAFFAUJEwAhAMgWAA==.Fitzchivalry:BAAALgAECgMJBgAAAA==.',
Fl='Fleethefield:BAAALgAECgYJEAAAAA==.Flowabridge:BAABLgAECn8WAAIHAAYJrwOvAgH2AAAHAAYJrwOvAgH2AAABLgAECggJKwATAK8SAA==.',
Fo='Foomanchu:BAAALgAECgQJBAABLgAECgYJEQAGAAAAAA==.Forcewild:BAABLgAECn8dAAIEAAcJ/h8JBwAmAgAEAAcJ/h8JBwAmAgAAAA==.',
Fr='Fragos:BAAALgAECgYJBwAAAA==.Friz:BAACLgAFFH8KAAMMAAQJgQhNDQCDAAALAAIJHAuOdQCQAAAMAAMJqgdNDQCDAAAuAAQKfyUAAwwACQmwHF4IADwCAAwACAmIH14IADwCAAsABQkZF8qeABsBAAAA.Frostychunks:BAABLgAECn8cAAIHAAgJdxtXMgANAgAHAAgJdxtXMgANAgAAAA==.',
Fu='Fuddrucker:BAAALgAECgkJDgAAAA==.Furflation:BAABLgAECn8hAAMYAAcJahh+CgDqAQAYAAcJahh+CgDqAQAaAAYJWx2bBgCYAQAAAA==.Furgam:BAAALgAECgEJAQAAAA==.Fury:BAAALgADCgYJCgABLgAECgQJBgAGAAAAAA==.Fuzzychunks:BAAALgAECgYJEwABLgAECggJHAAHAHcbAA==.',
Ga='Gabapentin:BAABLgAECn8UAAMiAAgJsBYDFADKAQAiAAgJsBYDFADKAQAVAAMJ6BdcQgDGAAAAAA==.Gaeren:BAAALgADCgkJEwAAAA==.Gal:BAAALgAECgEJAgAAAA==.Gannon:BAABLgAECn8kAAIHAAgJWBzgNQD/AQAHAAgJWBzgNQD/AQAAAA==.Gano:BAEALgAECgUJCAABLgAFFAQJDwABAKcUAA==.Garr:BAAALgAECgEJAgABLgAECgEJAwAGAAAAAA==.Garuuk:BAAALgAECgYJBgAAAA==.Gazir:BAAALgAECgkJEwAAAA==.',
Ge='Geniús:BAAALgADCgYJBgAAAA==.Genji:BAAALgAECgYJDQAAAA==.',
Gi='Giliandra:BAAALgADCggJDgAAAA==.',
Gl='Glitch:BAABLgAECn8nAAIWAAkJHAKFIADgAAAWAAkJHAKFIADgAAAAAA==.',
Gn='Gnxs:BAAALgAECgQJCwAAAA==.',
Go='Goonthar:BAACLgAFFH8LAAINAAUJZQ3HFwAcAQANAAUJZQ3HFwAcAQAuAAQKfywAAg0ACAmZI/oKAAQDAA0ACAmZI/oKAAQDAAAA.Gorethak:BAABLgAECn8VAAIBAAYJdxlnXgBkAQABAAYJdxlnXgBkAQAAAA==.',
Gr='Grannykul:BAAALgADCgEJAQAAAA==.Grindrage:BAAALgADCgEJAQAAAA==.Gripmedaddy:BAAALgAECgMJAwAAAA==.Grobble:BAAALgADCgkJHQAAAA==.Grollgrr:BAAALgAECgQJCAAAAA==.Grompo:BAAALgAECgQJBAABLgAECggJLgALAJEhAA==.Grompy:BAAALgADCgQJBAABLgAECggJLgALAJEhAA==.Gruffbeard:BAAALgAECgIJAgABLgAECgYJDwAGAAAAAA==.',
Gu='Gunee:BAAALgADCgEJAQAAAA==.Gunghoiguana:BAAALgAECgQJBwAAAA==.',
Gy='Gyattso:BAAALgAECgcJDAAAAA==.Gyxx:BAABLgAFFH8PAAMIAAQJ4RaoGgBVAQAIAAQJ4RaoGgBVAQAKAAMJfxjkHwDSAAAAAA==.',
Ha='Haddice:BAABLgAECn8YAAIHAAcJggnQgwA0AQAHAAcJggnQgwA0AQAAAA==.Hafarti:BAAALgADCgUJBAAAAA==.Hairyteeth:BAAALgAECgUJDgAAAA==.Hajime:BAABLgAECn8ZAAIhAAYJTQmeKwAaAQAhAAYJTQmeKwAaAQAAAA==.Halgrad:BAEALgAECgUJAQAAAA==.Hamburgers:BAAALgAECgEJAQAAAA==.Hansasperger:BAAALgAECgUJBwAAAA==.Harriedotter:BAAALgAECgEJAgAAAA==.Havárti:BAAALgADCgkJCQAAAA==.',
He='Heebiejeebie:BAABLgAECn9HAAQLAAkJhRrdHgAuAgALAAkJ4BjdHgAuAgAUAAUJbh68CgBFAQAMAAIJaQuDVwBoAAAAAA==.Hellaeus:BAABLgAECn8wAAIIAAgJDBwRKQAVAgAIAAgJDBwRKQAVAgAAAA==.Hellsong:BAAALgAECgYJBgAAAA==.Heresjohnny:BAAALgAECgIJAgAAAA==.',
Hi='Hinatasan:BAAALgAECgEJAgAAAA==.Hira:BAAALgAECgUJBQAAAA==.Hisokä:BAABLgAECn85AAIRAAkJSBSMDAD7AQARAAkJSBSMDAD7AQAAAA==.',
Ho='Hoku:BAAALgAECgMJBAAAAA==.Holycreambar:BAABLgAECn8qAAIIAAgJ/SDzGABuAgAIAAgJ/SDzGABuAgAAAA==.Holyjuan:BAAALgADCgkJEgAAAA==.Hoofsbane:BAAALgADCgcJBwAAAA==.',
Hu='Huntingale:BAAALgAECgMJAwAAAA==.Huntinshift:BAABLgAECn8VAAIFAAYJPwoucgD+AAAFAAYJPwoucgD+AAAAAA==.Huslangr:BAAALgADCgEJAQAAAA==.Huwn:BAAALgADCgQJBAAAAA==.',
Hy='Hygelak:BAABLgAECn8YAAIIAAYJpAbaqADcAAAIAAYJpAbaqADcAAAAAA==.Hypaxia:BAABLgAECn8VAAMcAAYJ7gyuFgDAAAAFAAYJ7gwRawAPAQAcAAYJtAeuFgDAAAABLgAECgYJFwAcAFkYAA==.',
Ib='Ibpowerline:BAAALgADCgYJBgAAAA==.',
Ic='Icethorn:BAAALgAECgIJAwABLgAECgMJAwAGAAAAAA==.',
Ig='Iggysmalls:BAABLgAECn8bAAMCAAkJBB36DgCMAgACAAkJBB36DgCMAgAXAAYJThIDDwAKAQAAAA==.',
Ii='Iidrizztdour:BAAALgADCgEJAQAAAA==.',
Il='Iluminaughti:BAAALgAECgYJCAAAAA==.',
Im='Immoc:BAACLgAFFH8OAAICAAQJRRz6HQBQAQACAAQJRRz6HQBQAQAuAAQKfy8AAwIACQl0HyohAIoCAAIACQl0HyohAIoCABcAAQnrCyQpACIAAAAA.',
In='Indy:BAABLgAECn8nAAIVAAgJLhMHIwCCAQAVAAgJLhMHIwCCAQAAAA==.Infidius:BAAALgADCggJEAAAAA==.Interés:BAAALgADCgQJBAAAAA==.Intodeep:BAAALgAECgkJDgAAAA==.Invocation:BAAALgAECgQJBQABLgAECgcJLgACAD8kAA==.',
Io='Iownyourcow:BAAALgAECgIJAgAAAA==.',
Ir='Iroha:BAAALgADCgYJBgAAAA==.Ironstag:BAAALgADCgQJBAAAAA==.',
Is='Istandalone:BAACLgAFFH8SAAMBAAUJSR4YLQBYAQABAAQJSR4YLQBYAQAeAAEJAAAWOAAAAAAuAAQKfxkAAgEACAm8Hy4hALwCAAEACAm8Hy4hALwCAAAA.',
Ix='Ixioth:BAAALgAECgEJAQAAAA==.',
Ja='Jaglok:BAAALgADCgEJAQAAAA==.Jagons:BAABLgAECn8YAAIjAAYJyAZeDwDqAAAjAAYJyAZeDwDqAAAAAA==.Jahfar:BAAALgAECgYJBwAAAA==.Jaken:BAAALgAECgEJAQAAAA==.Janara:BAAALgAECgUJCgAAAA==.',
Je='Jehtadin:BAAALgAECgkJEQAAAA==.Jehthero:BAAALgAECgYJCgABLgAECgkJEQAGAAAAAA==.Jehtshot:BAABLgAECn8cAAMcAAgJkRz9FQCBAgAcAAgJkRz9FQCBAgAFAAMJ3hxYiADPAAABLgAECgkJEQAGAAAAAA==.Jehtword:BAAALgAECgMJAwABLgAECgkJEQAGAAAAAA==.Jemjemner:BAAALgAECgEJAQAAAA==.Jesy:BAAALgAECgYJDAABLgAFFAQJDQAFACoZAA==.',
Ji='Jimvisible:BAACLgAFFH8IAAIgAAMJ+iPcEgA0AQAgAAMJ+iPcEgA0AQAuAAQKfx4AAyAABwm8Jj0FAJ8CACAABwm8Jj0FAJ8CACMAAQm/JWEXAGoAAAAA.',
Jo='Joan:BAAALgAECgIJAgABLgAFFAQJDAAHAHwXAA==.Johadro:BAAALgADCgEJAQAAAA==.',
Jr='Jr:BAAALgAECgMJBAAAAA==.',
Ju='Judgejobrown:BAAALgAECggJDgAAAA==.Judgenawt:BAABLgAECn8vAAIIAAkJth3DEACmAgAIAAkJth3DEACmAgAAAA==.Junon:BAAALgAECgUJCwAAAA==.',
Ka='Kain:BAABLgAECn8jAAILAAgJaw+tSgB8AQALAAgJaw+tSgB8AQAAAA==.Kaiá:BAAALgADCgUJBQAAAA==.Kalegard:BAAALgADCgcJDgAAAA==.Kalerah:BAAALgADCgYJBgAAAA==.Kalis:BAABLgAECn8hAAIHAAcJ+BCuegBFAQAHAAcJ+BCuegBFAQAAAA==.Kallum:BAAALgAECgYJEAAAAA==.Kaltak:BAAALgAECgIJAgAAAA==.Kalvynx:BAABLgAECn8hAAIVAAgJBRY2HAC7AQAVAAgJBRY2HAC7AQAAAA==.Karasu:BAAALgAECgMJBgAAAA==.Karn:BAABLgAECn8zAAIIAAkJJR4oDgC8AgAIAAkJJR4oDgC8AgAAAA==.Karti:BAAALgAECgMJAwAAAA==.Karzdormi:BAEALgAECgcJDAAAAA==.Kathell:BAAALgAECgIJBAABLgAFFAQJDQAFACoZAA==.Kaylly:BAAALgAECgQJBAABLgAECggJJwASAJAUAA==.Kayllynt:BAAALgADCggJFAABLgAECggJJwASAJAUAA==.Kayyllynt:BAABLgAECn8nAAMSAAgJkBQ9IwDqAQASAAgJkBQ9IwDqAQATAAIJYBG7TwB0AAAAAA==.',
Ke='Kegeraetor:BAACLgAFFH8PAAIJAAQJ5xt8EQBDAQAJAAQJ5xt8EQBDAQAuAAQKfzAAAgkACQlTIowRAO0BAAkACQlTIowRAO0BAAAA.Keinthdra:BAACLgAFFH8JAAMeAAMJWxE3HQCIAAAeAAIJ9Bg3HQCIAAABAAEJKQKpuwBCAAAuAAQKfzcAAx4ACQkrHc8MAEICAB4ACAkUHs8MAEICAAEABQkiE2KjANoAAAAA.Kelein:BAAALgAECgEJAQABLgAECgQJBgAGAAAAAA==.Keliste:BAAALgAECgUJCQAAAA==.Kema:BAAALgAECgcJDgAAAA==.Kennaea:BAAALgAECgIJAgABLgAFFAQJDwAHAMMSAA==.Kervana:BAAALgAECgMJBAABLgAFFAUJEwAhAMgWAA==.',
Kh='Khrysais:BAAALgADCgMJAwAAAA==.',
Ki='Killigula:BAABLgAECn8xAAINAAkJgRotDgBHAgANAAkJgRotDgBHAgAAAA==.Kinuye:BAAALgAECgMJAwAAAA==.Kishara:BAAALgAECgMJAwABLgAFFAQJDQAFACoZAA==.Kiwi:BAAALgAECgIJAwAAAA==.',
Kl='Klondor:BAABLgAECn8vAAQkAAgJsgqxHABqAQAkAAgJ5QmxHABqAQAFAAYJHgkagQDaAAAcAAIJxwF5fwBIAAAAAA==.Klutch:BAAALgADCgUJCAAAAA==.',
Ko='Kohakuu:BAAALgADCgEJAQAAAA==.Korash:BAABLgAECn8VAAMLAAkJ9SFOTgBxAQALAAcJ9yFOTgBxAQAMAAIJ6CEcOwDIAAAAAA==.',
Kr='Kraio:BAABLgAECn8dAAIHAAYJVxabcwBTAQAHAAYJVxabcwBTAQAAAA==.Kraisa:BAAALgADCgQJBAAAAA==.Krak:BAAALgAECgEJAQAAAA==.Krakenbones:BAAALgAECgUJCwAAAA==.Krenolarian:BAAALgADCgUJBQAAAA==.Kronax:BAAALgADCgQJBAAAAA==.',
Kv='Kvoke:BAAALgAECgIJCQAAAA==.',
Ky='Kyranni:BAAALgAECgEJAwAAAA==.',
La='Lamora:BAAALgAECgYJEwAAAA==.Lampard:BAABLgAECn8XAAINAAgJnxJaMAA9AQANAAgJnxJaMAA9AQAAAA==.Laraj:BAABLgAECn8aAAIFAAYJ3xmRVABKAQAFAAYJ3xmRVABKAQAAAA==.Larissaqt:BAEBLgAECn8eAAIDAAkJVhnBBgAjAgADAAkJVhnBBgAjAgAAAA==.Latindk:BAAALgADCgMJAwAAAA==.Latinhunter:BAAALgAECgYJCwAAAA==.Latinmonk:BAAALgAECgUJCAAAAA==.Latinshamy:BAABLgAECn8ZAAIfAAYJYxidMwCGAQAfAAYJYxidMwCGAQAAAA==.Lavande:BAAALgAECgQJCgAAAA==.',
Le='Lealu:BAAALgAECgUJBAAAAA==.Leara:BAAALgAECgQJBwABLgAFFAQJDQAFACoZAA==.Legomyagro:BAAALgAECggJEwAAAA==.Lehaya:BAAALgAECgEJAQAAAA==.Leiasolo:BAAALgAECgQJBAAAAA==.Leonaá:BAAALgAECgkJEwABLgAECgkJKwAQACkkAA==.Lewpysoup:BAAALgAECgkJAQABLgAFFAQJBAAGAAAAAA==.',
Li='Lightfall:BAAALgADCgIJAgAAAA==.Lilbessy:BAABLgAECn8YAAIfAAcJmAPtXQDYAAAfAAcJmAPtXQDYAAAAAA==.Lishaliel:BAAALgADCgcJBwABLgAFFAQJDQAFACoZAA==.Lizy:BAAALgADCgQJBQABLgADCgkJGQAGAAAAAA==.Lizzia:BAAALgADCgQJBAAAAA==.',
Lo='Loopysoup:BAAALgAECgEJAQABLgAFFAQJBAAGAAAAAA==.Loopyswoop:BAAALgAECgcJDgABLgAFFAQJBAAGAAAAAA==.Lothriel:BAABLgAECn8tAAIlAAgJ2RfZAwA7AgAlAAgJ2RfZAwA7AgAAAA==.',
Lu='Lucid:BAAALgAECgEJAQAAAA==.Ludioduo:BAAALgAECgUJBgAAAA==.Luedayen:BAABLgAECn8oAAMQAAkJBxvWDwBoAgAQAAkJBxvWDwBoAgAdAAEJqgoyZAAwAAAAAA==.Lukesunwalkr:BAAALgAECgEJAQAAAA==.Lunabellz:BAABLgAECn8aAAITAAcJVQj+NQDkAAATAAcJVQj+NQDkAAAAAA==.Lunavia:BAABLgAECn8hAAIFAAcJ+h2wJAD/AQAFAAcJ+h2wJAD/AQAAAA==.Luxembourge:BAAALgAECgUJDgAAAA==.',
Ma='Maalgus:BAABLgAECn8UAAIJAAYJlB4OGACqAQAJAAYJlB4OGACqAQAAAA==.Maarajade:BAAALgAECgEJAQAAAA==.Mad:BAAALgAECgMJBgAAAA==.Magivyne:BAAALgAECgEJAQAAAA==.Mahota:BAAALgADCggJDwAAAA==.Makennah:BAAALgADCgcJBwAAAA==.Maladash:BAABLgAECn8eAAQCAAgJUBd/NAAnAgACAAgJUBd/NAAnAgAXAAMJZAfNHwBPAAARAAEJAgkXdAAxAAABLgAFFAQJBwAIACkRAA==.Malephar:BAAALgADCgMJAwAAAA==.Manachi:BAAALgAECgIJAgAAAA==.Margoul:BAAALgAECgEJAQAAAA==.Massfootmen:BAAALgADCgUJBQAAAA==.Matiowen:BAAALgADCgMJAwAAAA==.Mauie:BAAALgADCgEJAQAAAA==.Mayyhem:BAACLgAFFH8dAAIYAAcJZRzCAQB1AgAYAAcJZRzCAQB1AgAuAAQKfyoAAxgACQkNI3kBAG8DABgACQkNI3kBAG8DABoAAgnfGegvAJgAAAAA.Mazrethil:BAAALgADCgEJAQAAAA==.',
Mc='Mcallister:BAABLgAECn8vAAISAAcJPB28HQAQAgASAAcJPB28HQAQAgABLgADCgkJGQAGAAAAAA==.Mcjudgin:BAABLgAECn8bAAQDAAgJZiXeAABnAwADAAgJZiXeAABnAwAKAAMJSxUoTQCrAAAIAAEJCh1YLAFIAAAAAA==.Mcsquid:BAAALgAECgEJAQAAAA==.',
Md='Mdrakeyd:BAABLgAECn8TAAICAAYJkRdbVgAyAQACAAYJkRdbVgAyAQAAAA==.',
Me='Meatbubble:BAAALgADCgkJFAAAAA==.Mechee:BAAALgAECggJCAAAAA==.Mephisston:BAAALgADCgIJAgAAAA==.Mesasneaky:BAAALgAECgUJBQAAAA==.',
Mi='Mimi:BAAALgAECgMJAwAAAA==.Mimiker:BAABLgAECn8nAAQZAAkJJxx1DQCeAgAZAAkJJxx1DQCeAgAaAAcJgRZzEgC6AQAYAAEJQwGtSQAvAAAAAA==.Minime:BAAALgAFFAIJBAABLgAFFAcJIwAFANEgAA==.Minininja:BAAALgADCgcJDAABLgAECgQJEgAGAAAAAA==.Miniobi:BAAALgAECgIJAwAAAA==.Mirabella:BAAALgAECgYJDwAAAA==.Mistdemeanor:BAAALgAECgEJAgAAAA==.Mizahella:BAAALgAECgMJBAAAAA==.',
Mo='Mofassa:BAAALgADCgEJAQAAAA==.Mokei:BAAALgAECgQJBAAAAA==.Mokushi:BAAALgAECgYJDQAAAA==.Mollie:BAAALgADCgcJBwABLgADCgkJFAAGAAAAAA==.Mondragore:BAAALgAECgQJBAAAAA==.Monkgruff:BAAALgAECgYJDwAAAA==.Monkèy:BAAALgADCgUJBQAAAA==.Moonsilver:BAAALgAECgkJDgAAAA==.Moriko:BAABLgAECn8yAAIFAAkJUBwAFgCIAgAFAAkJUBwAFgCIAgAAAA==.Mornak:BAAALgAECgkJCAAAAA==.Mourn:BAAALgAECgEJAQABLgAFFAQJDwAJAOcbAA==.',
Mu='Muertomarrow:BAAALgAECgYJDQAAAA==.Mulroth:BAAALgAECgQJBAAAAA==.Murdermitten:BAAALgAECgEJAgABLgAECgEJAwAGAAAAAA==.Murloc:BAAALgAECgYJCgAAAA==.Musasa:BAABLgAECn8kAAISAAgJphmtIAA+AgASAAgJphmtIAA+AgAAAA==.Mustardseed:BAABLgAECn81AAILAAkJsREYLgDhAQALAAkJsREYLgDhAQAAAA==.Muxaro:BAAALgAECgMJAwAAAA==.',
['Mí']='Mísery:BAAALgAECgYJDQAAAA==.',
Na='Naked:BAAALgAECgIJAwAAAA==.Nalibeefcake:BAAALgADCgcJDQAAAA==.Narkoleptick:BAAALgAECgYJCQAAAA==.Nasrith:BAABLgAECn8yAAIIAAkJwh2FDQDBAgAIAAkJwh2FDQDBAgAAAA==.Nastro:BAAALgAECgMJBgAAAA==.Naughtica:BAAALgAECgMJBgABLgAECgYJCAAGAAAAAA==.Nawtishot:BAAALgADCgEJAQAAAA==.Nazanath:BAAALgAECgIJAgAAAA==.',
Ne='Neeb:BAABLgAECn8dAAIDAAgJMBm6DAChAQADAAgJMBm6DAChAQAAAA==.Neeber:BAAALgAECgUJDQAAAA==.Neebtacular:BAAALgADCgYJBgAAAA==.Nekk:BAABLgAECn8hAAIWAAcJIxr+DgCqAQAWAAcJIxr+DgCqAQAAAA==.',
Ni='Niamyau:BAAALgADCgMJAwAAAA==.Niraleth:BAAALgAECgIJAgAAAA==.Nitebrite:BAABLgAECn8bAAIQAAYJ4hLZKAA2AQAQAAYJ4hLZKAA2AQAAAA==.',
No='Noatak:BAAALgAECgEJAgAAAA==.Nohozis:BAAALgADCgQJBAAAAA==.Noimia:BAABLgAECn8uAAIVAAkJNBzBCQCcAgAVAAkJNBzBCQCcAgAAAA==.Noraina:BAAALgADCgEJAQAAAA==.Normanosborn:BAAALgAECgQJCgAAAA==.',
Ny='Nyquiil:BAAALgADCgkJCQAAAA==.Nyssil:BAAALgADCgcJCwAAAA==.',
['Né']='Nésa:BAAALgAECgMJAwAAAA==.',
['Nï']='Nïssan:BAAALgAECgYJDwAAAA==.',
Ob='Obscûr:BAABLgAECn8VAAMCAAYJJA7YcQDrAAACAAUJxQ3YcQDrAAARAAUJHg1oKwC/AAAAAA==.',
Oc='Ochtli:BAAALgADCgUJBQAAAA==.',
Od='Oden:BAABLgAECn8UAAIOAAgJMxu6EAAbAgAOAAgJMxu6EAAbAgAAAA==.',
Og='Oggy:BAAALgAECgIJAgAAAA==.',
Ok='Oksanabaiul:BAABLgAECn8XAAIOAAUJDx5GKQBOAQAOAAUJDx5GKQBOAQABLgAFFAQJCwALAMUbAA==.',
Ol='Oldcode:BAAALgAECgUJCgAAAA==.Oleyander:BAAALgAECgMJBgAAAA==.Olskigather:BAAALgADCgMJAwAAAA==.Olskimonk:BAAALgAECgUJCgAAAA==.',
Or='Orondrean:BAAALgADCgEJAQAAAA==.Oronin:BAAALgAECgMJAwAAAA==.',
Os='Osanyin:BAAALgAECgcJEgAAAA==.',
Ot='Otsuka:BAAALgADCgEJAQAAAA==.',
Pa='Pacoesfu:BAAALgADCgcJBgAAAA==.Padray:BAACLgAFFH8OAAIdAAQJ6g7jDwA6AQAdAAQJ6g7jDwA6AQAuAAQKf0AAAh0ACQkEHQgJAHYCAB0ACQkEHQgJAHYCAAAA.Paecos:BAAALgADCgYJDQAAAA==.Palize:BAAALgADCgYJBgABLgAECgcJCwAGAAAAAA==.Panhia:BAAALgAECgQJEgAAAA==.Parliament:BAAALgAECgYJCwAAAA==.',
Pe='Pekoyami:BAAALgADCgUJBQAAAA==.Pen:BAABLgAECn8rAAITAAgJrxJHHQCEAQATAAgJrxJHHQCEAQAAAA==.Pepenlock:BAAALgAECgQJBQAAAA==.Pepperbottom:BAABLgAECn8eAAMMAAgJIhqXBgCjAQAMAAgJnRmXBgCjAQALAAQJ+BD7ggD2AAAAAA==.',
Pf='Pfft:BAAALgAECgQJBgAAAA==.',
Ph='Phantasmshot:BAABLgAECn8iAAIFAAgJaA7USgBnAQAFAAgJaA7USgBnAQAAAA==.Phoebere:BAAALgAECgMJBgAAAA==.Phung:BAAALgAECggJDAAAAA==.Phungi:BAAALgAECgYJDAAAAA==.',
Po='Polymnia:BAAALgAECgUJDAAAAA==.Pomelo:BAAALgAECgMJBgAAAA==.Popeums:BAABLgAECn8hAAMhAAcJ/wMHMwDnAAAhAAcJkwIHMwDnAAAQAAQJwgQ+RQCAAAAAAA==.Poplock:BAAALgADCgYJBgAAAA==.Poppiqt:BAABLgAECn8bAAIVAAcJZBXBHwCdAQAVAAcJZBXBHwCdAQAAAA==.Powlie:BAAALgAECgMJAwAAAA==.Poyoh:BAABLgAECn8yAAISAAkJ1htFDQCxAgASAAkJ1htFDQCxAgAAAA==.',
Pr='Pravoce:BAAALgAECgYJDAAAAA==.Prolifichd:BAAALgAECgEJAgABLgAECgEJAwAGAAAAAA==.Prufrock:BAAALgADCgYJBgAAAA==.',
['Pí']='Pínt:BAABLgAECn8hAAMFAAcJ/CN8GABHAgAFAAcJnCJ8GABHAgAkAAYJtB7SDgDZAQAAAA==.',
Qu='Quelissa:BAAALgADCgkJCQABLgAECgMJBAAGAAAAAA==.',
Ra='Radjason:BAAALgADCggJCQAAAA==.Raeagald:BAAALgAECgIJBAABLgAFFAQJDwAJAOcbAA==.Raelyni:BAABLgAECn83AAIQAAkJ+RsoBwC6AgAQAAkJ+RsoBwC6AgAAAA==.Rafael:BAAALgADCgMJAwAAAA==.Rageroyal:BAAALgADCgEJAQAAAA==.Rahum:BAAALgAECgQJBQAAAA==.Rakkah:BAABLgAECn8hAAMFAAcJBBV1UwBOAQAFAAcJuxJ1UwBOAQAcAAYJaQlRTgAXAQAAAA==.Rakkuh:BAAALgAECgQJBAAAAA==.Ramjam:BAAALgADCgYJCQAAAA==.Ranann:BAAALgAECgQJBAAAAA==.Rangwashu:BAAALgAECgYJDAABLgAECgYJFAAEAAkTAA==.Raveniss:BAABLgAECn8VAAITAAYJsweMPgC8AAATAAYJsweMPgC8AAAAAA==.Rawrie:BAABLgAECn8hAAMOAAgJcQfUNAANAQAOAAgJcQfUNAANAQAfAAMJsglogwCGAAAAAA==.Raygun:BAABLgAECn8YAAIHAAcJ/g4HcQBYAQAHAAcJ/g4HcQBYAQABLgADCgkJGQAGAAAAAA==.Rayzorevoker:BAAALgADCgcJDQAAAA==.Raziell:BAAALgADCgMJAwAAAA==.',
Re='Redhilda:BAABLgAECn8YAAIOAAYJ7Ah8TACrAAAOAAYJ7Ah8TACrAAAAAA==.Redmayhem:BAAALgADCgYJBgAAAA==.Remygos:BAAALgADCgEJAQAAAA==.',
Rh='Rhymu:BAAALgAECgMJAwAAAA==.',
Ri='Rissaria:BAAALgAECgIJAgAAAA==.',
Ro='Roshelle:BAAALgAECgIJAgAAAA==.Rotation:BAAALgAECgYJEQAAAA==.Rotblade:BAABLgAECn8aAAImAAkJ2BebBQC3AQAmAAkJ2BebBQC3AQAAAA==.',
Ru='Rudewenn:BAAALgAECgYJCQAAAA==.Runandhide:BAABLgAECn8VAAIHAAYJmhDXuQBuAQAHAAYJmhDXuQBuAQAAAA==.',
Ry='Ryllativity:BAAALgADCgEJAQAAAA==.',
['Ró']='Rógue:BAAALgAECgEJAQAAAA==.',
['Rø']='Røøtsftw:BAAALgAECgYJBgAAAA==.',
Sa='Sadsnap:BAABLgAECn8YAAInAAcJxyBECQBFAgAnAAcJxyBECQBFAgAAAA==.Safetybear:BAAALgAECgkJCQAAAA==.Salamender:BAACLgAFFH8IAAIYAAQJEhImEgARAQAYAAQJEhImEgARAQAuAAQKfywAAhgACQmdG5QDAMgCABgACQmdG5QDAMgCAAAA.Sapheer:BAAALgAECgUJBQABLgAECgcJDwAGAAAAAA==.Sargothys:BAAALgAECgIJAgAAAA==.Sariais:BAAALgAECgEJAQAAAA==.Sassymoo:BAACLgAFFH8HAAISAAMJ9Q1/KgDMAAASAAMJ9Q1/KgDMAAAuAAQKfxgAAxIABwlhHE4ZADMCABIABwlhHE4ZADMCAAQAAQmPBME6ABEAAAEuAAUUBAkLAB8ApBYA.Sathenoth:BAAALgADCggJCAAAAA==.Savagejoker:BAAALgAECgEJAQABLgAECggJIQAoAL4iAA==.Sañtoro:BAAALgAECgQJDQAAAA==.',
Sc='Scalesboi:BAAALgADCgMJAwAAAA==.Scipione:BAAALgAECgYJEQAAAA==.Scy:BAAALgAECgcJEQAAAA==.',
Se='Seddona:BAAALgADCgkJCQAAAA==.Seithe:BAAALgADCgkJCQAAAA==.Seluun:BAABLgAECn8jAAIHAAYJ5BGogwA0AQAHAAYJ5BGogwA0AQAAAA==.Semandemon:BAAALgAECgEJAQAAAA==.Sephandrius:BAAALgADCgEJAQABLgAECgYJFAAEAAkTAA==.Seraphae:BAAALgAECgYJEQAAAA==.',
Sh='Shadowmorn:BAABLgAECn8dAAIOAAgJJQNTRQDFAAAOAAgJJQNTRQDFAAAAAA==.Shalako:BAAALgAECgEJAQAAAA==.Shambali:BAAALgAECgcJBwAAAA==.Shamidozz:BAAALgAECgQJBQABLgAECgcJKAAKAFcWAA==.Shamnistic:BAABLgAECn8iAAMnAAkJrh9AAwCMAgAnAAkJrh9AAwCMAgAfAAEJyg2UnQAqAAAAAA==.Shandro:BAABLgAECn8tAAIHAAkJfgsHUACpAQAHAAkJfgsHUACpAQAAAA==.Shaniallon:BAABLgAECn8tAAMFAAkJNhHaKgDhAQAFAAkJExHaKgDhAQAcAAcJdgtaEAAMAQAAAA==.Shara:BAAALgADCgMJBgAAAA==.Sharana:BAAALgADCgUJBQAAAA==.Shaunï:BAAALgAECgYJDAAAAA==.Sheriff:BAAALgAECgEJAQAAAA==.Shieldman:BAAALgADCgMJAwAAAA==.Shiftylock:BAABLgAECn8dAAMEAAYJKhwQEAB0AQAEAAYJKhwQEAB0AQAbAAMJYRYFIgDKAAAAAA==.Shine:BAAALgAECgMJAwAAAA==.Showong:BAAALgAECgEJAQAAAA==.',
Si='Silentaska:BAABLgAECn8ZAAIZAAYJoSEJHQCdAQAZAAYJoSEJHQCdAQAAAA==.Silentbruce:BAAALgAECgYJBwAAAA==.Silentchill:BAABLgAECn8pAAMTAAgJrx37FwBKAgATAAgJrx37FwBKAgASAAEJBQLP5AAgAAAAAA==.Silius:BAAALgAECgUJDAAAAA==.Simoncrunch:BAAALgAECgEJBQAAAA==.Sin:BAAALgAECgEJAQABLgAECgEJAwAGAAAAAA==.Sinomen:BAABLgAECn8lAAInAAkJiiPRAAAcAwAnAAkJiiPRAAAcAwABLgAFFAUJDAAFACsPAA==.Sinzilla:BAAALgAECgYJDQAAAA==.Sizzen:BAAALgADCgkJCQAAAA==.',
Sk='Skunkdrunk:BAAALgADCgYJBwAAAA==.Skyblue:BAAALgAECgYJEQAAAA==.',
Sm='Smokebull:BAABLgAECn8WAAINAAcJ8gp9OgALAQANAAcJ8gp9OgALAQAAAA==.Smolcat:BAAALgAECgQJBAABLgAFFAcJHQAYAGUcAA==.',
Sn='Sneeble:BAAALgADCgkJCQAAAA==.Snoopshaman:BAAALgAECgEJAQABLgAECggJGwADAGYlAA==.Snowcake:BAAALgAECgEJBwAAAA==.',
So='Sofiavers:BAAALgAECgQJBAAAAA==.Solarhoof:BAAALgADCgEJAQAAAA==.Sonarak:BAAALgAECgEJAQABLgAECggJGwADAGYlAA==.Sornafayne:BAAALgAECgQJBAAAAA==.Sorrengail:BAABLgAECn8ZAAIfAAYJwSJ8FwA5AgAfAAYJwSJ8FwA5AgAAAA==.Soulvamp:BAAALgADCgUJBQAAAA==.',
Sp='Spareme:BAAALgAECgQJCAABLgAECgkJDgAGAAAAAA==.Specialkidd:BAAALgAECgkJDwAAAA==.Springrollz:BAAALgAECggJCAABLgAFFAcJIwAFANEgAA==.Spy:BAABLgAECn8tAAIFAAgJeRxWHAAtAgAFAAgJeRxWHAAtAgAAAA==.',
Sr='Sravoz:BAAALgAECgYJCQAAAA==.',
St='Stabbitha:BAAALgADCgkJHAAAAA==.Stampa:BAAALgAECgQJBwAAAA==.Starrie:BAABLgAECn85AAMfAAgJmRFeNACCAQAfAAgJmRFeNACCAQAOAAcJigx9NQAJAQAAAA==.Steaknshake:BAAALgAECgQJBAAAAA==.Steelhoof:BAABLgAECn8yAAIcAAkJfg5fCQCTAQAcAAkJfg5fCQCTAQAAAA==.Steil:BAAALgAECgMJAwAAAA==.Steponmyface:BAABLgAECn8pAAMBAAgJIiL8EwCQAgABAAgJIiL8EwCQAgAlAAIJzxunFwCKAAAAAA==.Stewie:BAAALgADCgcJCgABLgADCgkJFAAGAAAAAA==.Stonesoul:BAABLgAECn8aAAMfAAkJ6RfGEAB4AgAfAAkJ6RfGEAB4AgAOAAEJ3wsrfQAqAAAAAA==.Stories:BAABLgAECn8VAAIHAAYJ0BhmoACWAQAHAAYJ0BhmoACWAQABLgAECgcJCwAGAAAAAA==.Storm:BAEALgAECgYJCgABLgAFFAQJDwABAKcUAA==.Stormfury:BAAALgAECgEJAwAAAA==.Strucker:BAAALgADCgcJCwABLgAECgkJMgAJAJQgAA==.Struckerdots:BAAALgAECgQJBAABLgAECgkJMgAJAJQgAA==.Struckerz:BAAALgADCgkJEAABLgAECgkJMgAJAJQgAA==.Struckerzz:BAAALgAECgQJBwAAAA==.Struckrucker:BAABLgAECn8yAAIJAAkJlCCVAwDnAgAJAAkJlCCVAwDnAgAAAA==.Stygian:BAAALgAECgEJAQAAAA==.',
Su='Sudimmoc:BAAALgAECgIJAgAAAA==.Sugarbear:BAAALgADCgUJBQAAAA==.Sushie:BAAALgADCgMJAwABLgAFFAUJEAAKABITAA==.',
Sv='Svikja:BAAALgAECgQJBwAAAA==.',
Sw='Swipe:BAAALgAECgcJCgAAAA==.',
Sy='Synn:BAAALgADCgkJEgAAAA==.Syvina:BAABLgAECn8UAAIhAAYJrAjNLAASAQAhAAYJrAjNLAASAQAAAA==.',
Ta='Tabby:BAAALgAECgIJBQAAAA==.Taconight:BAABLgAECn8ZAAIQAAYJygXwNwDRAAAQAAYJygXwNwDRAAAAAA==.Tacosaladin:BAAALgADCggJCAAAAA==.Tag:BAAALgAECgYJCAAAAA==.Takyon:BAAALgADCgYJBgABLgAECggJFgABALcjAA==.Tallynz:BAABLgAECn8ZAAIQAAkJnBZXCgB2AgAQAAkJnBZXCgB2AgAAAA==.Tankornot:BAAALgAECgUJEAAAAA==.Tarasque:BAAALgAECgEJAQABLgAECgEJBwAGAAAAAA==.Tarlgreyhair:BAAALgAECgQJBQAAAA==.Tarnished:BAABLgAECn8dAAIHAAkJwwKpnwABAQAHAAkJwwKpnwABAQAAAA==.Tarria:BAABLgAECn8VAAIIAAcJcBZIUQCLAQAIAAcJcBZIUQCLAQAAAA==.Tateerfel:BAABLgAECn8bAAICAAYJVx/tNQCjAQACAAYJVx/tNQCjAQAAAA==.Tateertot:BAAALgADCgkJGwABLgAECgYJGwACAFcfAA==.Tawneestone:BAABLgAECn85AAIWAAkJ1yQJAQBAAwAWAAkJ1yQJAQBAAwAAAA==.',
Te='Teedizzle:BAAALgAECgUJBQAAAA==.Teek:BAABLgAECn8YAAMUAAYJwAQXFQDfAAAUAAYJnAIXFQDfAAALAAYJwARRnQDDAAAAAA==.Telandaraa:BAABLgAECn8rAAMQAAkJKSS6AQBdAwAQAAkJKSS6AQBdAwAhAAMJFgn8RACRAAAAAA==.Telrae:BAABLgAECn8sAAILAAkJqB87CgDQAgALAAkJqB87CgDQAgAAAA==.',
Th='Theb:BAAALgAECgkJEwAAAA==.Thederpb:BAAALgAECggJEQAAAA==.Thejuice:BAAALgADCgcJDwAAAA==.Theldara:BAACLgAFFH8NAAIFAAQJKhn/EwBaAQAFAAQJKhn/EwBaAQAuAAQKfzAAAwUACQkoITAsANsBAAUACQkoITAsANsBABwABgkTFlk7AHMBAAAA.Themock:BAABLgAECn8UAAMTAAYJkw6ZPwC3AAATAAQJnAyZPwC3AAASAAMJawIUrQAwAAAAAA==.Thereaper:BAAALgAECgMJAwAAAA==.Theresjohnny:BAAALgADCgkJGwAAAA==.Theshift:BAABLgAECn8kAAIhAAgJhxONGAC0AQAhAAgJhxONGAC0AQAAAA==.Thesixtyone:BAAALgADCgcJBwAAAA==.Thisisjustin:BAABLgAECn8mAAIpAAkJWh7DAACbAgApAAkJWh7DAACbAgAAAA==.Thoreen:BAAALgAECgMJBgAAAA==.Thotsnprayer:BAAALgADCgMJBAAAAA==.Thraiel:BAAALgADCgQJBAABLgAECgUJDgAGAAAAAA==.Thrish:BAACLgAFFH8MAAMFAAQJkRCEJQAnAQAFAAQJow2EJQAnAQAkAAIJZBQ/GQCsAAAuAAQKfzUABAUACQmRHu8cAFgCAAUACAm7Ge8cAFgCACQABgn/HvITAL4BABwAAQkFAoiYAB4AAAAA.Throom:BAAALgADCgIJAgAAAA==.Thuggies:BAAALgAECgYJDgAAAA==.Thunderfist:BAAALgAECgUJBwABLgAFFAQJBwAIACkRAA==.',
Ti='Tizzlerizzle:BAAALgAECgMJAwAAAA==.',
To='Tomacco:BAAALgADCggJEgAAAA==.Toreto:BAAALgADCgUJBwAAAA==.Toshi:BAAALgAECgQJBwAAAA==.Totemiclord:BAABLgAECn8aAAIOAAgJRA63KQBLAQAOAAgJRA63KQBLAQAAAA==.',
Ts='Tsukiyami:BAAALgAECgUJDwABLgAECgYJDAAGAAAAAA==.',
Tw='Twixaldo:BAAALgAECgQJBgABLgAECggJKgAIAP0gAA==.',
Ty='Ty:BAAALgADCgEJAQAAAA==.Tylus:BAAALgADCgcJEAAAAA==.',
Ub='Ubpriest:BAAALgAECgMJAwAAAA==.',
Up='Upinya:BAABLgAECn8YAAMMAAkJSAprDQAZAQAMAAkJSAprDQAZAQALAAEJ+QCnMgEcAAAAAA==.',
Ut='Uthrob:BAAALgADCgUJBQAAAA==.',
Uz='Uzumaki:BAAALgAECgQJBAAAAA==.',
Va='Vadderung:BAABLgAECn8aAAICAAgJNhyXKgBWAgACAAgJNhyXKgBWAgAAAA==.Valera:BAAALgAECgYJCwABLgAECgkJOQAPAM0lAA==.Valkilmer:BAAALgADCgEJAQAAAA==.Vallasha:BAABLgAECn8gAAIUAAcJHRG4CQBYAQAUAAcJHRG4CQBYAQAAAA==.Valoth:BAAALgADCgEJAQAAAA==.Valtures:BAAALgAECgMJCAAAAA==.Vampyre:BAACLgAFFH8JAAIFAAQJhhdRGwBEAQAFAAQJhhdRGwBEAQAuAAQKfyYAAgUABwlpJNUUAGICAAUABwlpJNUUAGICAAAA.Vayne:BAACLgAFFH8RAAINAAQJ/x6CDABVAQANAAQJ/x6CDABVAQAuAAQKfzUAAw0ACQnnJL8RAMICAA0ACQnnJL8RAMICAA8AAQksEwdBADYAAAAA.',
Ve='Vejek:BAAALgAECgkJBQAAAA==.Veloistina:BAAALgADCggJDAABLgAECggJKgAIAP0gAA==.Veloria:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.Venator:BAAALgADCgQJBAAAAA==.',
Vh='Vh:BAAALgAECgQJCAAAAA==.',
Vi='Videlle:BAAALgADCgMJAwAAAA==.Vieoree:BAAALgAECgUJDAAAAA==.Vigoh:BAAALgADCgcJBwABLgAECgYJEwAGAAAAAA==.Vinge:BAECLgAFFH8PAAIBAAQJpxSsOABEAQABAAQJpxSsOABEAQAuAAQKfzIAAgEACQmKIuotAIECAAEACQmKIuotAIECAAAA.Vinter:BAAALgADCgkJEwAAAA==.Violetferal:BAAALgADCggJGQAAAA==.Violetrain:BAABLgAECn8iAAIIAAcJKQSwrgDTAAAIAAcJKQSwrgDTAAAAAA==.Viralswine:BAAALgAECgcJCgAAAA==.Visarys:BAAALgAECgQJBAAAAA==.Vixipixi:BAAALgADCgYJEgAAAA==.',
Vo='Vollibear:BAAALgAECgMJAwAAAA==.Voltaic:BAABLgAECn8bAAIfAAcJNCMdEgCFAgAfAAcJNCMdEgCFAgABLgAECgcJLgACAD8kAA==.Vothdomosh:BAAALgADCgcJGAABLgAECgcJGQAKAF8kAA==.',
Vy='Vyrista:BAABLgAECn8UAAIRAAcJyA5BHAAxAQARAAcJyA5BHAAxAQAAAA==.Vyrzeth:BAAALgAECgMJBgAAAA==.Vyzualize:BAACLgAFFH8SAAIKAAUJzBWFBACYAQAKAAUJzBWFBACYAQAuAAQKfygAAgoACQl0IKoHAPICAAoACQl0IKoHAPICAAAA.',
Wa='Wae:BAABLgAECn8XAAIeAAkJ6R0NBgCBAgAeAAkJ6R0NBgCBAgAAAA==.Waferblade:BAAALgADCgcJBwAAAA==.Waknipi:BAABLgAECn8hAAMIAAkJchxOGAByAgAIAAkJchxOGAByAgAKAAEJIQUEnAAtAAAAAA==.Wauwen:BAAALgADCgkJGQAAAA==.Wavecheck:BAAALgAECgMJBQAAAA==.Way:BAAALgAECgIJAgAAAA==.Waycaps:BAACLgAFFH8NAAIXAAQJRx6WAQBYAQAXAAQJRx6WAQBYAQAuAAQKfy0AAhcACAk2I9ABAPgCABcACAk2I9ABAPgCAAAA.',
We='Wednesdáy:BAABLgAECn8eAAMNAAcJPhOJPwCmAQANAAcJPhOJPwCmAQAWAAEJfAyOPwAxAAAAAA==.Werlock:BAAALgAECgcJCgABLgAECgkJJQAZANMNAA==.Wetton:BAAALgAECgQJBQAAAA==.',
Wh='Wheresjohnny:BAABLgAECn83AAIeAAkJyBtBBwBhAgAeAAkJyBtBBwBhAgAAAA==.',
Wi='Wiccked:BAABLgAECn8nAAIUAAgJ0he3BAArAgAUAAgJ0he3BAArAgAAAA==.Windrange:BAACLgAFFH8NAAIHAAQJdhB5PQA/AQAHAAQJdhB5PQA/AQAuAAQKfy0AAgcACQmuIFcrAMUCAAcACQmuIFcrAMUCAAAA.Winterice:BAAALgAECgQJBQAAAA==.Wintérhoof:BAAALgAECgEJAQABLgAECgUJCQAGAAAAAA==.',
Wo='Wonderpally:BAAALgADCgkJCQAAAA==.Woodscale:BAAALgAECgMJBgAAAA==.Wovenbones:BAAALgAECgYJEAAAAA==.',
Wu='Wuggs:BAAALgAECgIJAgABLgAFFAQJEQAHANQgAA==.Wumbo:BAAALgADCgYJDAAAAA==.',
Wy='Wyvarn:BAAALgAECgcJEgAAAA==.',
Xa='Xargothys:BAAALgAECgYJDQAAAA==.',
Xi='Xiisle:BAABLgAECn8dAAIIAAcJOCY6FACNAgAIAAcJOCY6FACNAgAAAA==.Xine:BAAALgADCgkJFAAAAA==.',
Xt='Xt:BAAALgADCgUJBQAAAA==.',
Xy='Xynara:BAAALgAECgkJEQAAAA==.',
Ya='Yanya:BAAALgAECgMJBAAAAA==.',
Ye='Yergat:BAACLgAFFH8jAAQFAAcJ0SAqBwCfAQAFAAUJpSMqBwCfAQAcAAcJ+hksDQBNAQAkAAMJ7xJHEwD3AAAuAAQKfzgABBwACQkrJe8BAJ0DABwACQn1Iu8BAJ0DACQACQljIzABAC4DAAUAAwnwIllmADQBAAAA.',
Yo='Yongu:BAAALgADCgkJCQAAAA==.',
Yu='Yupa:BAABLgAECn8YAAIWAAcJlBv8DADMAQAWAAcJlBv8DADMAQABLgAECgkJMgAFAFAcAA==.',
Za='Zafira:BAACLgAFFH8LAAIfAAQJpBboGQAsAQAfAAQJpBboGQAsAQAuAAQKfyUAAx8ACQm7GloRAIwCAB8ACQm7GloRAIwCAA4AAwnmDOVxAHsAAAAA.Zainea:BAAALgAECgEJAQABLgAFFAQJCwAfAKQWAA==.Zarndarg:BAAALgAECgQJBAAAAA==.Zartuu:BAAALgAECgcJCQAAAA==.Zattani:BAAALgAECgQJBgAAAA==.',
Ze='Zeel:BAAALgAECgUJBQAAAA==.Zelblades:BAAALgAECgYJDQABLgAECgkJKQAgAPgdAA==.Zelrex:BAABLgAECn8pAAMgAAkJ+B1zDwCtAgAgAAkJ+B1zDwCtAgAjAAEJphQjHQBCAAAAAA==.Zerat:BAAALgAECgMJAwAAAA==.Zerazer:BAACLgAFFH8LAAIaAAUJYyKoAACZAQAaAAUJYyKoAACZAQAuAAQKfxQAAhoACQmfIbMCAEsCABoACQmfIbMCAEsCAAAA.',
Zh='Zhuntyr:BAABLgAECn8WAAIFAAYJEhAOYwAiAQAFAAYJEhAOYwAiAQAAAA==.',
Zi='Ziggedion:BAABLgAECn8UAAIZAAkJYQgpJwBSAQAZAAkJYQgpJwBSAQAAAA==.Zindar:BAABLgAECn8hAAIZAAcJWx4XFADwAQAZAAcJWx4XFADwAQAAAA==.Ziyan:BAAALgAECgkJCQABLgAECgkJDwAGAAAAAA==.',
Zv='Zv:BAAALgADCgUJBQAAAA==.',
Zy='Zylos:BAAALgADCgYJBwAAAA==.Zynzz:BAAALgAECgQJBwAAAA==.',
['Zô']='Zômi:BAAALgAECgMJBwAAAA==.',
['Àg']='Àgony:BAAALgAECgcJBwAAAA==.',
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
