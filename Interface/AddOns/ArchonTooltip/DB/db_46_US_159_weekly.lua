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

local lookup = {'Rogue-Outlaw','Mage-Frost','Shaman-Enhancement','Priest-Shadow','DemonHunter-Devourer','Monk-Windwalker','Hunter-BeastMastery','Unknown-Unknown','Monk-Brewmaster','DeathKnight-Blood','Warrior-Fury','Evoker-Preservation','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Mistweaver','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Priest-Discipline','DeathKnight-Unholy','Warlock-Demonology','Hunter-Survival','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Warlock-Affliction','Priest-Holy','Paladin-Retribution','Mage-Arcane','Paladin-Protection','Shaman-Restoration','Druid-Guardian','Shaman-Elemental','Mage-Fire','Warrior-Arms','Paladin-Holy','Druid-Balance','Warrior-Protection','Druid-Feral','Warlock-Destruction','DeathKnight-Frost',}
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=46,date='2026-06-06',data={Ac='Acense:BAAALgAECgcJDQAAAA==.Acesham:BAAALgAECgEJAQAAAA==.Acewing:BAAALgADCgkJCgAAAA==.Acidlock:BAAALgAECgEJAgAAAA==.Acidpriest:BAAALgAECgkJDwAAAA==.Acidshaman:BAAALgADCgYJBwAAAA==.',
Ad='Adacey:BAABLgAECn8UAAIBAAcJ+hONCQCGAQABAAcJ+hONCQCGAQAAAA==.Ademeo:BAAALgAFFAEJAQABLgAFFAYJIQACAOkUAA==.Adragon:BAAALgAECggJDwAAAA==.Adrenalized:BAAALgAECgIJAgAAAA==.',
Ae='Aedryll:BAAALgAECgYJDQAAAA==.Aeriden:BAAALgAECgEJAQAAAA==.Aesuga:BAABLgAECn9EAAIDAAkJEiaEAABlAwADAAkJEiaEAABlAwAAAA==.Aethelflaed:BAABLgAECn8wAAIEAAgJQB3eDwBWAgAEAAgJQB3eDwBWAgAAAA==.',
Ag='Agnolotti:BAAALgAECgUJCAAAAA==.',
Ai='Aimedjupiter:BAAALgAECgYJEQABLgAFFAUJDwAFAMUYAA==.Air:BAAALgADCgcJBwABLgAECgkJGQAGAGoZAA==.Airlyn:BAABLgAECn8oAAIHAAcJxw3tbQBZAQAHAAcJxw3tbQBZAQAAAA==.Aisen:BAAALgADCgEJAQABLgAECgEJAQAIAAAAAA==.',
Ak='Aktras:BAAALgAECgUJDwAAAA==.',
Al='Alaunu:BAAALgAECgUJBQABLgAECgkJJwAJAPMIAA==.Aleas:BAAALgAECgQJDAAAAA==.Aliciab:BAAALgADCgYJEAAAAA==.Alkaid:BAAALgAECgEJAQAAAA==.Alndvia:BAAALgAECgcJEwAAAA==.Alponkster:BAAALgADCggJEwAAAA==.Alunia:BAAALgAECgQJCgAAAA==.Alytheal:BAAALgAECgEJAQABLgAECgkJIgAKAHAdAA==.',
Am='Americow:BAAALgAECgIJAgAAAA==.',
An='Anari:BAAALgAECgEJAQABLgAECgcJBwAIAAAAAA==.Anarky:BAABLgAECn8yAAILAAgJyARyTwABAQALAAgJyARyTwABAQAAAA==.Andarnah:BAAALgADCgQJBAAAAA==.Annebonny:BAAALgADCgkJCQAAAA==.Annunaki:BAAALgAECgIJAwAAAA==.Anthrfinpete:BAAALgAECgYJDQABLgAECggJKAAMABkUAA==.Anze:BAAALgAECgIJAgAAAA==.',
Ar='Arathenes:BAAALgADCgcJCQAAAA==.Araylen:BAAALgADCgEJAQAAAA==.Archae:BAAALgAECgEJAQAAAA==.Archdemon:BAABLgAECn8rAAMNAAkJDxhCCADkAQANAAkJDxhCCADkAQAOAAEJWRt5ZQBOAAAAAA==.Ariannette:BAAALgAECgMJAwAAAA==.Arilyn:BAAALgADCgMJAwAAAA==.Arkhanx:BAAALgAECgUJDAAAAA==.Artemisia:BAAALgAECgQJCAAAAA==.Artichoke:BAABLgAECn8cAAMOAAkJHhAcKQAhAQAOAAcJohIcKQAhAQAFAAUJTAeivwCdAAAAAA==.',
As='Ashamane:BAAALgAECgYJCQABLgAECgUJDAAIAAAAAA==.Ashanara:BAAALgADCgEJAQABLgAECgkJMwAPAOoZAA==.Asheril:BAAALgAECgQJBQAAAA==.Ashy:BAAALgADCgUJBQAAAA==.Astrov:BAACLgAFFH8FAAIOAAIJMw09HwCBAAAOAAIJMw09HwCBAAAuAAQKfxsAAw4ACQmfE/gTAOQBAA4ACQmfE/gTAOQBAAUABQmEDLqnAMEAAAAA.',
At='Athera:BAAALgADCggJCAAAAA==.',
Au='Auani:BAABLgAECn8wAAIQAAkJhCOAAwCEAwAQAAkJhCOAAwCEAwAAAA==.Augtistic:BAABLgAECn9BAAMRAAkJ+yP9AwAoAwARAAkJ+yP9AwAoAwASAAMJwRfbKwC+AAAAAA==.Aurani:BAAALgAECgEJAQAAAA==.',
Aw='Awyeahdaddy:BAAALgADCgMJAwAAAA==.',
Ay='Ayanna:BAAALgADCgkJFQAAAA==.',
Az='Azale:BAAALgAECgMJAwAAAA==.Azazyl:BAAALgAECgYJBgAAAA==.Azimuth:BAAALgAECgYJBgAAAA==.Azraél:BAAALgAECgEJAQAAAA==.Azulagos:BAAALgADCgYJBgAAAA==.Azzeus:BAACLgAFFH8HAAIEAAMJOxFrIQDRAAAEAAMJOxFrIQDRAAAuAAQKfxwAAwQACQm8GLoRAEECAAQACQm8GLoRAEECABMAAQmbEx9XADMAAAAA.',
Ba='Baawb:BAAALgAECgEJAQABLgAECggJIgAUAFkYAA==.Babyrinsjr:BAABLgAECn8rAAIHAAgJtxsJJABHAgAHAAgJtxsJJABHAgAAAA==.Baeyn:BAAALgAECgcJDAABLgAFFAMJBQAVAA4VAA==.Bagel:BAACLgAFFH8KAAMHAAQJ3hUKNgA2AQAHAAQJ3hUKNgA2AQAWAAMJCAkYAwDMAAAuAAQKfyAABBYACAnIGvgkAHEBABcABQkBFy86AHgBABYABwkJHPgkAHEBAAcABgn9DFVVAGgBAAEuAAUUBgkiAAMAPyYA.Baile:BAAALgAECgEJAQAAAA==.Bakon:BAAALgAECgUJDAAAAA==.Balin:BAAALgADCgYJDgAAAA==.Ballerin:BAAALgADCggJDwABLgAECgYJDQAIAAAAAA==.Bamm:BAAALgAECgQJCAAAAA==.Bamsplat:BAAALgADCgYJDQAAAA==.Barrada:BAABLgAECn8kAAIHAAgJoQsrawBfAQAHAAgJoQsrawBfAQAAAA==.Barricay:BAAALgAECgYJBwAAAA==.Bathroy:BAAALgADCgIJAgAAAA==.',
Be='Bearcane:BAAALgADCgUJBQABLgAFFAUJFQAFANQNAA==.Beardheals:BAAALgAECgQJBAAAAA==.Beardàddy:BAAALgAECgQJBQAAAA==.Bellamira:BAAALgADCgIJAgAAAA==.Benjarrey:BAAALgAECgUJCgAAAA==.Berea:BAABLgAECn8kAAIYAAkJQwshCQClAQAYAAkJQwshCQClAQAAAA==.',
Bi='Bigmeatyclaw:BAAALgAECgEJBQAAAA==.Billywitchdr:BAAALgADCgEJAQAAAA==.',
Bl='Blankdemonic:BAAALgAECgEJAQAAAA==.Bleedblue:BAABLgAECn8yAAIZAAgJ9xlWFADyAQAZAAgJ9xlWFADyAQAAAA==.Blezzy:BAAALgADCgIJAgAAAA==.Bloaf:BAAALgAECgkJDQAAAA==.Blueballmonk:BAAALgAECgYJCgAAAA==.Bluerare:BAABLgAECn83AAICAAkJSxoHLABjAgACAAkJSxoHLABjAgAAAA==.',
Bo='Bobsgrundle:BAAALgAECgQJBAAAAA==.Bolty:BAAALgADCgUJBQAAAA==.Bonietta:BAAALgADCgIJAgAAAA==.Borahae:BAACLgAFFH8IAAIaAAQJjgK4CADhAAAaAAQJjgK4CADhAAAuAAQKfxYAAhoACQnBDB0KAK4BABoACQnBDB0KAK4BAAAA.Bowlinna:BAAALgAECgQJBwAAAA==.',
Br='Brewrosia:BAAALgAECgYJCgAAAA==.Briiki:BAAALgAECgEJAQAAAA==.Brinnohms:BAAALgAECgEJAQAAAA==.Broadsnatl:BAAALgADCgEJAQAAAA==.Bruddah:BAAALgADCgEJAQAAAA==.Brunnhild:BAAALgAECgYJEQAAAA==.Bryxi:BAABLgAECn8WAAIJAAkJxRBRHAC6AQAJAAkJxRBRHAC6AQABLgAECggJIgAUAFkYAA==.Brândle:BAAALgAECgIJAgAAAA==.Bríelle:BAAALgAECgQJBgAAAA==.Brünhilde:BAACLgAFFH8IAAMTAAIJ4wcsOgB4AAATAAIJ4wcsOgB4AAAbAAEJngHIOAAkAAAuAAQKfzEAAxMACQlRE0AbAOYBABMACQlRE0AbAOYBAAQAAgnNCeVrAF4AAAAA.',
Bs='Bstbll:BAACLgAFFH8aAAIQAAgJNxNFCQBIAgAQAAgJNxNFCQBIAgAuAAQKfxYAAhAACQmUHv4JAPQCABAACQmUHv4JAPQCAAAA.Bstwaves:BAAALgAECgQJBQAAAA==.',
Bu='Bubbleban:BAAALgADCgUJBQAAAA==.Bubbleheals:BAAALgAECgcJDAABLgAFFAUJEQADAFUNAA==.Bungxi:BAAALgADCgUJBgABLgAECggJIgAUAFkYAA==.Buraddo:BAAALgAECgYJDgABLgAECggJKwAcAHobAA==.Burrata:BAAALgADCgkJCQAAAA==.Buttsnacks:BAABLgAECn8mAAILAAkJOSEiDACgAgALAAkJOSEiDACgAgAAAA==.',
Ca='Caciocavallo:BAAALgAECgcJBwAAAA==.Cairebear:BAAALgAECgUJEgAAAA==.Callistrah:BAABLgAECn89AAMdAAkJ9xjUAgAHAgAdAAgJQBnUAgAHAgACAAgJkREzXgC+AQAAAA==.Caltaa:BAABLgAECn9FAAIeAAkJuyX4AABLAwAeAAkJuyX4AABLAwAAAA==.Camael:BAAALgAECggJEAAAAA==.Canarah:BAAALgADCgUJBQABLgAFFAQJEAAfAM0TAA==.Canverian:BAABLgAECn8rAAIgAAgJpRykCQA8AgAgAAgJpRykCQA8AgAAAA==.Carlyy:BAAALgAECgQJBAABLgAECgkJJAAfAIAZAA==.Carmedic:BAAALgADCgcJDQAAAA==.Carradine:BAAALgADCggJCQAAAA==.',
Ce='Celexa:BAAALgAECgkJDgABLgAECgQJEgAIAAAAAA==.Celtmon:BAAALgADCgIJBAAAAA==.',
Ch='Cha:BAAALgAECgEJAQABLgAECgEJAQAIAAAAAA==.Chapi:BAAALgAECgYJDQAAAA==.Chasseurfool:BAABLgAECn8XAAIHAAYJAQzPlQAHAQAHAAYJAQzPlQAHAQAAAA==.Chat:BAACLgAFFH8UAAIhAAYJZBzLEACFAQAhAAYJZBzLEACFAQAuAAQKfy8AAiEACQk2G88PAGwCACEACQk2G88PAGwCAAAA.Chevalieono:BAAALgADCgIJAgAAAA==.Chewi:BAAALgADCgEJAQAAAA==.Chezaro:BAAALgAECgcJDQAAAA==.Chickenlitle:BAAALgADCgUJBQAAAA==.Chickenwing:BAACLgAFFH8IAAIiAAIJux4uAwC2AAAiAAIJux4uAwC2AAAuAAQKfzoAAiIACQnKIL4AAOYCACIACQnKIL4AAOYCAAAA.Chilin:BAAALgAECgYJBwAAAA==.Chilindk:BAAALgAECgIJAgABLgAECgYJBwAIAAAAAA==.Chilinevoke:BAAALgAECgMJBAABLgAECgYJBwAIAAAAAA==.Christano:BAABLgAECn8iAAMcAAcJDBxjVADCAQAcAAcJ3xhjVADCAQAeAAUJoxuCGwAuAQAAAA==.Christhecold:BAABLgAECn9DAAMjAAkJZB2BDQAGAgAjAAcJqhqBDQAGAgALAAcJ4RcYOQDCAQAAAA==.Chrollo:BAABLgAECn8UAAIDAAYJchUwFwBBAQADAAYJchUwFwBBAQAAAA==.Chronoknight:BAAALgADCgkJCQAAAA==.Chronson:BAAALgAECgYJBwAAAA==.Chunt:BAAALgAECgQJCQAAAA==.',
Cl='Clamscasino:BAAALgADCgIJAgABLgAECgcJJQAkAIgOAA==.Clarke:BAAALgADCgMJAwAAAA==.Closets:BAAALgAECgMJAwAAAA==.Cloudcrack:BAACLgAFFH8hAAIhAAgJRRPUCAD+AQAhAAgJRRPUCAD+AQAuAAQKfy8AAiEACQlfHzwNAIoCACEACQlfHzwNAIoCAAAA.Clynt:BAAALgADCgIJAgAAAA==.',
Co='Cocoapuffs:BAAALgADCgIJAgABLgAECgkJQAAKAMUfAA==.Cocotaso:BAAALgAFFAMJBAAAAA==.Codemon:BAABLgAECn8qAAMSAAgJbROMDQApAQARAAgJUQ05NABWAQASAAYJSRaMDQApAQAAAA==.Coldfusion:BAAALgADCgkJCgAAAA==.Condemn:BAAALgADCgEJAgAAAA==.Condiments:BAAALgAECgEJAgAAAA==.Cortar:BAABLgAECn8XAAIcAAgJFhSkfQBoAQAcAAgJFhSkfQBoAQAAAA==.Cotw:BAAALgAECgIJAwABLgAECggJDwAIAAAAAA==.',
Cp='Cptcharis:BAAALgADCgYJBgAAAA==.',
Cu='Cubann:BAAALgAECgMJBgAAAA==.',
Cy='Cylrhea:BAABLgAECn8gAAMQAAgJESV8BgBJAwAQAAgJESV8BgBJAwAlAAIJ+AVQfABDAAAAAA==.Cyntrill:BAAALgAECgUJDAAAAA==.',
Cz='Czeralsmok:BAAALgAECgEJAQAAAA==.',
Da='Dadderz:BAAALgAECgUJDAAAAA==.Daddydruid:BAAALgAECgQJBgAAAA==.Daemonyx:BAAALgADCgkJGwABLgAECgUJDAAIAAAAAA==.Dahunter:BAABLgAECn8YAAIWAAgJsBpaEAAoAgAWAAgJsBpaEAAoAgAAAA==.Dajoel:BAAALgAECgYJDQAAAA==.Dakinna:BAAALgADCgMJAwAAAA==.Dakotawolfe:BAAALgADCgUJBQAAAA==.Dalacia:BAACLgAFFH8FAAIfAAIJGhyaTwCgAAAfAAIJGhyaTwCgAAAuAAQKfyAAAh8ACQk3EyMyAN0BAB8ACQk3EyMyAN0BAAAA.Dalarik:BAAALgAECgEJAwAAAA==.Dannyrojas:BAAALgAECgEJAgAAAA==.Daphera:BAAALgAECggJDQAAAA==.Darkforceray:BAAALgAECgEJAgAAAA==.Darknature:BAABLgAECn8zAAMQAAkJchKMLwDcAQAQAAkJchKMLwDcAQAlAAcJmBByPAAQAQAAAA==.Darkodin:BAABLgAECn8pAAIUAAgJWgsPgQBYAQAUAAgJWgsPgQBYAQAAAA==.Darkomen:BAAALgADCgcJGQABLgAECggJLgAUAFYQAA==.Darkvlad:BAABLgAECn8uAAIUAAgJVhC0ZACWAQAUAAgJVhC0ZACWAQAAAA==.Datnagadrake:BAACLgAFFH8fAAMLAAYJ8BkmCwCaAQALAAYJ8BkmCwCaAQAmAAIJXxUVCwCWAAAuAAQKf0MAAwsACQmMJGcDAC4DAAsACQmMJGcDAC4DACYAAgldHvExAKgAAAAA.Davere:BAAALgADCgEJAQAAAA==.Dawinchy:BAACLgAFFH8XAAIQAAUJAw+EIgA4AQAQAAUJAw+EIgA4AQAuAAQKf00ABBAACQmIFEg0ANcBABAACQmIFEg0ANcBACcABwlyC/AbABgBACUAAQmnBSCYACEAAAAA.',
Dc='Dchalla:BAAALgADCgcJDQAAAA==.',
De='Deadlypsycho:BAABLgAECn8VAAILAAYJlhcaOABeAQALAAYJlhcaOABeAQAAAA==.Deadmanrise:BAAALgADCgUJBQAAAA==.Deathawakens:BAABLgAFFH8LAAIZAAQJDgxpHgAcAQAZAAQJDgxpHgAcAQAAAA==.Deathchanges:BAAALgAECgIJAQABLgAECgcJEwANAE4RAA==.Deathlyill:BAABLgAECn8TAAINAAcJThE1EAA6AQANAAcJThE1EAA6AQAAAA==.Deathtouch:BAAALgADCgcJDAAAAA==.Decembër:BAABLgAECn80AAICAAgJLgkajQBXAQACAAgJLgkajQBXAQAAAA==.Decimious:BAAALgAECgQJBwAAAA==.Dejarl:BAAALgADCgQJBAAAAA==.Dekutree:BAABLgAECn8jAAMgAAkJpQ2bHQBNAQAgAAkJpQ2bHQBNAQAnAAEJsQPAVAAkAAAAAA==.Dellistia:BAAALgAECgYJDwAAAA==.Delvan:BAAALgAECgIJAgAAAA==.Demiglace:BAAALgAECgYJDwAAAA==.Demonkilla:BAAALgAECgYJDwAAAA==.Denadan:BAAALgAECgQJBQABLgAECgkJNAAaANELAA==.Desdamona:BAABLgAECn8iAAIHAAgJUAU+hQAnAQAHAAgJUAU+hQAnAQAAAA==.Destrodeath:BAABLgAECn8WAAIUAAkJ3g6gTQDTAQAUAAkJ3g6gTQDTAQAAAA==.Destrodemon:BAABLgAECn8jAAIFAAgJEhLfYQBYAQAFAAgJEhLfYQBYAQAAAA==.Destrosham:BAAALgAECgYJBgAAAA==.Deviltango:BAAALgAECgQJBAAAAA==.Devorick:BAABLgAECn84AAMVAAkJPBt+IABcAgAVAAkJPBt+IABcAgAoAAIJQxCqUQB5AAAAAA==.Deztaknee:BAAALgAECgQJCQAAAA==.',
Di='Diadem:BAAALgAECgMJBAABLgAFFAMJBQAVAA4VAA==.Diathian:BAAALgAECgUJBwABLgAFFAYJIQACAOkUAA==.Diaval:BAABLgAECn8lAAIcAAYJcgfm3ADVAAAcAAYJcgfm3ADVAAAAAA==.Dih:BAAALgAECgIJAgABLgAECgkJJgAWAMEQAA==.Dihlngthepal:BAAALgAECgEJAQAAAA==.Dirtyzealot:BAAALgADCgkJFwAAAA==.Disenchanted:BAAALgAECgYJBgABLgAFFAMJCAARAHIVAA==.Divineknight:BAAALgADCgkJFQAAAA==.Diyiya:BAAALgAECgYJCwAAAA==.',
Dk='Dkchex:BAAALgAECgQJBAAAAA==.',
Dn='Dnkys:BAAALgAECgQJBAAAAA==.',
Do='Dokoth:BAAALgADCgEJAQAAAA==.Doorki:BAAALgAFFAIJBAAAAA==.Doubleott:BAABLgAECn8XAAIHAAcJlRHmYQB1AQAHAAcJlRHmYQB1AQAAAA==.Doxycycline:BAAALgADCgMJAwABLgAECgYJEwAIAAAAAA==.',
Dr='Drael:BAAALgAECgUJCgAAAA==.Dragonayre:BAAALgAECgUJCQABLgAFFAMJBQAVAA4VAA==.Draickin:BAABLgAECn83AAIkAAgJkhstEQCCAgAkAAgJkhstEQCCAgAAAA==.Dreamfire:BAAALgAECgEJAQAAAA==.Drekle:BAABLgAECn8eAAMMAAgJdxBTFAB+AQAMAAcJ4xBTFAB+AQARAAUJeAm9UADfAAAAAA==.Drelian:BAAALgAECgUJCgAAAA==.Drenzel:BAAALgADCgYJCQAAAA==.Drevy:BAABLgAECn8WAAQZAAcJHhb/KgAxAQAZAAcJHhb/KgAxAQABAAMJOgiTDABdAAAYAAEJAAAcLQAAAAAAAA==.Drewsguy:BAAALgAECgUJDwAAAA==.Drexchan:BAAALgAECgYJEAAAAA==.Drexen:BAAALgADCgQJBQAAAA==.Drexy:BAAALgAECgEJAQAAAA==.Drhoger:BAAALgAECgYJDQAAAA==.Dropdahammer:BAAALgADCgUJBQAAAA==.Drumma:BAAALgAECgYJEQAAAA==.Drumroleplz:BAACLgAFFH8IAAMRAAMJchW5OQDQAAARAAMJchW5OQDQAAASAAEJJA2XDQBFAAAuAAQKfx0AAxEACAlzG2EnAJ4BABIABgnKHZkTAKsBABEABwnsFWEnAJ4BAAAA.',
Ds='Dsanatrestk:BAABLgAECn8oAAMUAAkJ3iT/EwDIAgAUAAkJ3iT/EwDIAgAKAAcJ1RpaEAAFAgAAAA==.',
Du='Dumbguy:BAAALgAECgYJCgABLgAECgkJJwAVAJgiAA==.Dumbman:BAAALgAECgcJCgABLgAECgkJJwAVAJgiAA==.',
Dw='Dw:BAAALgADCgYJCgAAAA==.',
['Dà']='Dàddybear:BAABLgAECn8ZAAIHAAkJRBDCaQBiAQAHAAkJRBDCaQBiAQAAAA==.',
Ea='Earthsangel:BAAALgAECggJDgAAAA==.',
Ec='Eclair:BAABLgAFFH8RAAIeAAQJ2BLUBwDtAAAeAAQJ2BLUBwDtAAAAAA==.',
Ed='Edralyia:BAAALgAECgYJDwAAAA==.',
Ei='Eilaurosa:BAABLgAECn9BAAIYAAkJ/BgfBABRAgAYAAkJ/BgfBABRAgAAAA==.Einnarr:BAAALgAECgYJBgAAAA==.',
El='Eldrinne:BAABLgAECn8dAAIiAAgJ4QUcCAD7AAAiAAgJ4QUcCAD7AAAAAA==.Elftuah:BAAALgADCggJCAAAAA==.Elfö:BAABLgAECn8VAAIHAAkJThVzQgDPAQAHAAkJThVzQgDPAQAAAA==.Elizawrath:BAABLgAECn86AAMeAAkJhSP2AQAWAwAeAAkJhSP2AQAWAwAkAAUJlBHkWgARAQAAAA==.Elkuco:BAAALgAECgIJAgAAAA==.Elthiss:BAABLgAECn9DAAIgAAgJaRwYCwAfAgAgAAgJaRwYCwAfAgAAAA==.Elusuma:BAAALgAECgkJBwAAAA==.',
Em='Emariel:BAAALgAFFAEJAQAAAA==.',
En='Enchäntress:BAACLgAFFH8KAAIVAAMJ0QQbgwCtAAAVAAMJ0QQbgwCtAAAuAAQKfx4AAxUACQnmDQ1YAJABABUACQnmDQ1YAJABABoAAQkAAIM3ACMAAAAA.Enfer:BAAALgADCgYJCAABLgAFFAYJFAAhAGQcAA==.Enogg:BAAALgAECgYJCQAAAA==.Envi:BAABLgAECn9AAAMCAAkJQBsnKABzAgACAAkJQBsnKABzAgAdAAEJWRUmEwA/AAAAAA==.',
Ep='Ephraìm:BAAALgAECgcJBwAAAA==.',
Er='Erianthe:BAABLgAECn80AAIUAAkJswrRYwCYAQAUAAkJswrRYwCYAQAAAA==.Eroar:BAAALgADCgYJBgAAAA==.Erophien:BAAALgADCgkJLAABLgAECgcJHAAWABsIAA==.Erovael:BAAALgADCgQJBAABLgAECgcJHAAWABsIAA==.Erovynael:BAABLgAECn8cAAMWAAcJGwgALgAxAQAWAAcJGwgALgAxAQAHAAQJeAP9zgCYAAAAAA==.',
Ev='Eversong:BAAALgAECgYJEQAAAA==.Evhi:BAAALgAECgYJCQAAAA==.',
Ex='Exmar:BAAALgAECgMJAwAAAA==.',
Fa='Faewhisker:BAAALgAECgQJBAAAAA==.Faey:BAAALgADCgQJBAAAAA==.Falnor:BAAALgADCgkJDAABLgAECgkJKwAEAHsaAA==.Famine:BAACLgAFFH8IAAMKAAMJ2Q3iJgCoAAAKAAMJcwziJgCoAAAUAAIJXQ030gCHAAAuAAQKfyQAAxQACQloHPIxAHACABQACQloHPIxAHACACkAAQkAAPpAAAAAAAAA.Fancyfeet:BAAALgAFFAEJAQABLgAFFAYJHQAZANAZAA==.Fangmonarch:BAAALgADCgEJAQAAAA==.',
Fc='Fckmalfurion:BAAALgADCgkJEgABLgAECgkJJgAWAMEQAA==.',
Fe='Fearios:BAABLgAECn9AAAIKAAkJxR/tBQDAAgAKAAkJxR/tBQDAAgAAAA==.Febronia:BAAALgAECgUJBQAAAA==.Felbeast:BAAALgAECgYJBQAAAA==.Felbound:BAAALgAECgEJAQAAAA==.Felltheburn:BAAALgADCgEJAQAAAA==.',
Fi='Figmênt:BAAALgAECgUJDgABLgAECgcJJQAkAIgOAA==.Finatic:BAAALgAECgMJAwAAAA==.Finneous:BAABLgAECn8ZAAQGAAcJXho/HADAAQAGAAcJXho/HADAAQAJAAEJQh2ieABOAAAPAAEJlgOUwgAaAAAAAA==.Fireproof:BAABLgAECn8fAAMeAAcJjiKPCABPAgAeAAcJOiCPCABPAgAcAAcJXCD+OQA7AgAAAA==.Fistedwaffle:BAAALgAFFAMJAwABLgAFFAMJBAAIAAAAAA==.Fistopher:BAAALgAECgEJAQAAAA==.',
Fj='Fjorskin:BAAALgAECgQJBAAAAA==.',
Fl='Flairdragin:BAAALgAECgYJDQAAAA==.Flare:BAAALgAECggJEgAAAA==.',
Fo='Forix:BAAALgADCggJDAAAAA==.',
Fr='Fries:BAAALgADCggJCAAAAA==.Frosttbyte:BAACLgAFFH8HAAICAAQJeRELVAA1AQACAAQJeRELVAA1AQAuAAQKfx0AAgIACQlwHC0rAGYCAAIACQlwHC0rAGYCAAAA.Frostytute:BAAALgADCgcJEQAAAA==.Frozenwitch:BAAALgADCgUJBQAAAA==.',
Fu='Fullmetalass:BAAALgADCggJCAABLgAECgIJAgAIAAAAAA==.Funnelcake:BAAALgADCgkJCAAAAA==.Funsies:BAAALgADCgEJAQAAAA==.',
Fy='Fyrrstorm:BAAALgAECgMJAwAAAA==.',
['Fë']='Fëiróx:BAAALgADCgYJBgAAAA==.',
Ga='Gallum:BAAALgADCgEJAQAAAA==.Gamuza:BAAALgAECgQJBAAAAA==.',
Ge='Getzi:BAABLgAECn8cAAIcAAkJ4CH8FQDlAgAcAAkJ4CH8FQDlAgAAAA==.',
Gh='Ghavinflip:BAABLgAECn8XAAIGAAgJARKNJACCAQAGAAgJARKNJACCAQAAAA==.',
Gi='Gil:BAABLgAECn87AAIFAAkJCyNjBwAPAwAFAAkJCyNjBwAPAwAAAA==.Gimlita:BAAALgAECgIJAgABLgAECggJIgAUAFkYAA==.Gindraxx:BAAALgADCgEJAQAAAA==.',
Gl='Glocket:BAAALgADCgEJAQAAAA==.',
Go='Goatspace:BAAALgADCgcJDgABLgAECgkJNAAaANELAA==.Goettel:BAAALgAECgUJBQAAAA==.Gogmazios:BAAALgADCgEJAQAAAA==.Gogofisco:BAAALgAECgEJAgAAAA==.Gongagà:BAAALgAECgYJDAAAAA==.Goodnoodle:BAAALgADCgEJAQAAAA==.Gothbaddie:BAAALgAECgcJBwAAAA==.Goyum:BAAALgAECgQJBwAAAA==.',
Gr='Grankino:BAABLgAECn8iAAInAAcJKRhxDwCtAQAnAAcJKRhxDwCtAQAAAA==.Grapenuts:BAAALgADCgEJAQABLgAECgkJQAAKAMUfAA==.Grayves:BAAALgAECgUJBAAAAA==.Greenthumbs:BAABLgAECn8ZAAIlAAgJNAgCPgAJAQAlAAgJNAgCPgAJAQAAAA==.Greyhulk:BAABLgAECn8YAAMUAAcJKQ7rmwApAQAUAAcJKQ7rmwApAQAKAAUJhwbvQgB2AAAAAA==.Grinlock:BAAALgADCgEJAQAAAA==.',
Gu='Guldanshower:BAAALgADCgIJAgAAAA==.Gurni:BAAALgADCgYJCAAAAA==.Guthan:BAAALgAECgEJAQAAAA==.Guthild:BAAALgAECgIJAgAAAA==.',
Gw='Gwaelphypha:BAABLgAECn8iAAMUAAgJWRj9RAAmAgAUAAgJnBf9RAAmAgAKAAcJlBFCIwAtAQAAAA==.',
Ha='Hakarii:BAAALgADCgYJDAAAAA==.Halder:BAAALgAECgEJAQAAAA==.Halliax:BAAALgADCgYJBgABLgAFFAMJBQAVAA4VAA==.Hamburglar:BAAALgADCgYJCAAAAA==.Hamdaul:BAAALgADCgUJBQAAAA==.Hapkido:BAABLgAECn9HAAQPAAkJtyQMAgCpAwAPAAkJtyQMAgCpAwAJAAEJxwklmgAiAAAGAAEJcgQjrAAhAAAAAA==.Hardsus:BAAALgAECgQJAwAAAA==.Hauwitzer:BAAALgAECgQJBQAAAA==.Hawfmave:BAAALgAECgcJEQAAAA==.',
He='Heals:BAAALgAECgMJAwAAAA==.Healsmcnasty:BAAALgADCgEJAQAAAA==.Healthpotion:BAAALgAECgMJAwAAAA==.Heartbroken:BAAALgAECgkJBwAAAA==.Hecate:BAABLgAECn8bAAIcAAgJKAVGvgD+AAAcAAgJKAVGvgD+AAAAAA==.Heidnik:BAAALgAECgQJDAAAAA==.Helvetica:BAAALgADCggJDwAAAA==.Heretic:BAAALgAECgUJDAAAAA==.Hessdemon:BAABLgAECn8XAAMNAAgJFgVvHwCSAAAFAAgJIQRIogDRAAANAAYJlQRvHwCSAAAAAA==.',
Hi='Hillboy:BAAALgAFFAIJBAAAAA==.Hippiehulk:BAAALgAECgEJAQAAAA==.',
Ho='Holydes:BAAALgAECgUJDwABLgAECggJIgAHAFAFAA==.Holyfrejoles:BAAALgAECgkJAwAAAA==.Holyshrimp:BAABLgAECn85AAIEAAkJIR6ACADCAgAEAAkJIR6ACADCAgAAAA==.Honeydew:BAAALgAECgkJAQABLgAECgkJAgAIAAAAAA==.Hordor:BAAALgAECgEJAQAAAA==.Hotndot:BAAALgADCgcJCgAAAA==.',
Hu='Humboldt:BAAALgAECgEJAQABLgAECgcJBwAIAAAAAA==.Hummakavulä:BAAALgAECgUJDAAAAA==.Hunkahunka:BAAALgAECgMJBAAAAA==.Huunaron:BAABLgAECn8lAAMkAAkJqhmXGQAuAgAkAAkJqhmXGQAuAgAcAAQJUwcDAQGoAAABLgAFFAQJBgATAJISAA==.',
Ic='Ichmochtewie:BAAALgAECgMJAwAAAA==.',
Id='Idylwilde:BAABLgAECn8YAAMlAAYJPwYdVQCsAAAlAAYJPwYdVQCsAAAnAAEJOgfIVwAgAAAAAA==.',
Ie='Ienzo:BAAALgADCgUJBQAAAA==.',
If='Ifunny:BAAALgAECgcJCgAAAA==.',
Ih='Iheartoreos:BAABLgAECn80AAMKAAkJMhTnFQCwAQAKAAkJIBTnFQCwAQApAAQJLwnwDgCzAAAAAA==.',
Il='Ilikeoreos:BAAALgADCgEJAQAAAA==.Illiblades:BAAALgAECgQJBAABLgAFFAYJGAAOAPgiAA==.Ilovefuta:BAACLgAFFH8KAAIJAAMJgRcULwDhAAAJAAMJgRcULwDhAAAuAAQKfxUAAgkACQntHuMGAMICAAkACQntHuMGAMICAAAA.',
In='Ineedoreos:BAAALgAECgYJCQAAAA==.Inferna:BAAALgAECgUJBgAAAA==.Infidelis:BAAALgAECgEJAQAAAA==.Ink:BAABLgAFFH8GAAIUAAMJfxbpOwClAAAUAAMJfxbpOwClAAAAAA==.Inmortuae:BAAALgAECgMJAwAAAA==.Instakill:BAAALgADCgYJCQAAAA==.Insulin:BAAALgADCgkJEgAAAA==.Invictae:BAABLgAECn8hAAQTAAgJtRFjHQDVAQATAAgJtRFjHQDVAQAEAAcJEgsvOQAmAQAbAAQJwAwMTgCYAAAAAA==.',
Io='Iobo:BAACLgAFFH8bAAIFAAgJEB+MDQAnAgAFAAgJEB+MDQAnAgAuAAQKfxgAAgUACQl4Ig8HAFYDAAUACQl4Ig8HAFYDAAAA.',
Ir='Iradori:BAABLgAFFH8hAAICAAYJ6RTOMwCHAQACAAYJ6RTOMwCHAQAAAA==.Irønbane:BAAALgAECgEJAQAAAA==.',
Is='Iskandar:BAAALgAECgYJCgAAAA==.Ismarck:BAAALgADCgYJBgAAAA==.Isparian:BAABLgAECn8wAAQcAAgJ1hp8SwDaAQAcAAgJdBl8SwDaAQAeAAUJLA5yKQDAAAAkAAEJiwmpjwAqAAAAAA==.Issior:BAAALgAECgMJAwAAAA==.',
Ja='Jaegar:BAAALgADCgIJAgAAAA==.Jamal:BAAALgADCgkJGwAAAA==.Jarco:BAEBLgAFFH8QAAQHAAYJlRuvJQBcAQAHAAUJmR+vJQBcAQAXAAIJhQt2LQBOAAAWAAEJigSDMABBAAAAAA==.Jasmyn:BAAALgADCgEJAQAAAA==.Jasseca:BAAALgADCggJCAABLgAECggJIgAUAFkYAA==.Java:BAABLgAECn8aAAIVAAcJURFDdQBKAQAVAAcJURFDdQBKAQAAAA==.',
Je='Jeandarc:BAAALgADCgkJCQAAAA==.',
Jo='Joedakilla:BAAALgAECgEJAQAAAA==.Jonorin:BAAALgADCgEJAQAAAA==.',
Js='Jshaman:BAABLgAECn8bAAMfAAYJ6wdZiwCxAAAfAAUJ9gdZiwCxAAAhAAYJkgRIaACeAAAAAA==.',
Ju='Judoken:BAABLgAECn8VAAMZAAYJIAdeOQDYAAAZAAYJHAdeOQDYAAAYAAUJUwLnFACsAAAAAA==.Jupiterr:BAABLgAFFH8HAAMXAAMJvRk4EwAKAQAXAAMJvRk4EwAKAQAHAAEJkRPbkQBLAAABLgAFFAUJDwAFAMUYAA==.Justapotato:BAAALgADCgIJAgAAAA==.',
Ka='Kaadra:BAAALgAECgEJAQAAAA==.Kaeldach:BAAALgAECgYJCwAAAA==.Kaelgen:BAAALgAECggJCwAAAA==.Kaelkin:BAABLgAECn8aAAMTAAkJLReRDwBrAgATAAkJLReRDwBrAgAEAAEJDhsfcgBNAAABLgAECgkJKAADAEAWAA==.Kaelpae:BAAALgADCgUJBQABLgAECgkJKAADAEAWAA==.Kaelthlar:BAAALgAECgIJAwAAAA==.Kaelun:BAAALgAECgQJBwABLgAECgkJKAADAEAWAA==.Kaelundrus:BAABLgAECn8oAAMDAAkJQBabDADaAQADAAgJTBibDADaAQAfAAYJkBnERACMAQAAAA==.Kainis:BAABLgAECn8cAAIXAAcJtAftFwDnAAAXAAcJtAftFwDnAAAAAA==.Kairia:BAAALgADCgEJAQAAAA==.Kalvinakri:BAAALgADCgkJDgAAAA==.Karasana:BAAALgAECgQJBAAAAA==.Karmus:BAAALgAECggJEwAAAA==.Kastaspella:BAABLgAECn8cAAICAAcJnhBniQBeAQACAAcJnhBniQBeAQAAAA==.Kau:BAABLgAECn8VAAIYAAYJFQSuFgC4AAAYAAYJFQSuFgC4AAAAAA==.Kawant:BAAALgAECgIJAwAAAA==.Kaylnee:BAABLgAECn8nAAIfAAcJXxKlRQCJAQAfAAcJXxKlRQCJAQAAAA==.',
Ke='Keadin:BAAALgAECgYJEAAAAA==.Kearra:BAAALgADCgkJCQABLgAECgMJBwAIAAAAAA==.Kehayne:BAAALgADCgQJBAAAAA==.Keilas:BAABLgAECn8mAAInAAgJhR4qBgB3AgAnAAgJhR4qBgB3AgAAAA==.Kerro:BAAALgAECgIJAwAAAA==.Kerron:BAAALgADCgMJAwAAAA==.Keyes:BAACLgAFFH8qAAIJAAgJ2BiXAQD8AQAJAAgJ2BiXAQD8AQAuAAQKfycAAgkACQlsIRAIAKsCAAkACQlsIRAIAKsCAAAA.Keylala:BAABLgAECn8rAAMoAAgJkxRMCQCkAQAoAAgJkxRMCQCkAQAVAAIJTwRsFwFFAAAAAA==.',
Ki='Kiafera:BAAALgADCgMJAwAAAA==.Kibo:BAAALgAECgMJAwAAAA==.Kickenmage:BAAALgAECggJCQAAAA==.Kickentail:BAAALgAECgYJDwABLgAECggJCQAIAAAAAA==.Kidx:BAAALgAECgMJAwAAAA==.Kimjunggoon:BAAALgAECgEJAQAAAA==.Kimunkamuy:BAAALgAECgYJBgAAAA==.Kiraw:BAAALgAECgIJBAAAAA==.Kirisham:BAAALgAECgQJBAAAAA==.Kirlia:BAAALgAECgMJBgAAAA==.Kishenia:BAAALgAECgIJAgAAAA==.',
Kl='Kleanx:BAAALgADCgcJEwAAAA==.Klymax:BAAALgADCgUJBQAAAA==.',
Ko='Kongor:BAABLgAECn8pAAIDAAgJ9hzBCAAoAgADAAgJ9hzBCAAoAgAAAA==.Korathazan:BAAALgADCgEJAQAAAA==.Korithelse:BAAALgAECgEJAQAAAA==.Korthea:BAAALgAECgIJAgAAAA==.',
Kr='Krispitreat:BAAALgAECgYJCwAAAA==.Kritnespears:BAAALgAECgcJEgABLgAECggJDAAIAAAAAA==.Krobelus:BAABLgAECn89AAMcAAkJ5ww7cQCBAQAcAAkJ5ww7cQCBAQAkAAYJVQXpZADoAAAAAA==.Kryptik:BAAALgADCgEJAQAAAA==.',
Kv='Kvedaheillr:BAAALgAECgMJAwAAAA==.Kvedaroðull:BAAALgADCgYJBwAAAA==.Kvedathulr:BAAALgADCgYJBgAAAA==.',
Ky='Kyehole:BAAALgAECgMJBQAAAA==.Kylearean:BAAALgADCgYJBgAAAA==.Kyluna:BAAALgAECgEJAQAAAA==.',
['Kè']='Kères:BAAALgAECgYJDQAAAA==.Kèrónos:BAAALgAECgUJDwAAAA==.',
['Kì']='Kìllstheweak:BAABLgAECn8xAAMpAAkJGBArDwBxAQApAAkJVg8rDwBxAQAKAAYJ3QwPJwAGAQAAAA==.',
La='Lauralai:BAAALgAECgMJAwAAAA==.Lavendra:BAAALgADCgcJDwAAAA==.Lawkz:BAAALgAECgcJCAAAAA==.Layliah:BAACLgAFFH8fAAIlAAcJ6iFJBQA5AgAlAAcJ6iFJBQA5AgAuAAQKf0gAAiUACQlJJYEBAGYDACUACQlJJYEBAGYDAAAA.',
Le='Leafless:BAAALgAECgEJAQAAAA==.Leaftemplar:BAAALgADCgYJBgAAAA==.Leedragoon:BAAALgADCgMJAwAAAA==.Legaia:BAAALgADCgYJCQAAAA==.Legendknewl:BAAALgAECgQJBAAAAA==.Leilara:BAAALgADCgcJCwAAAA==.Lemmesapthat:BAAALgADCgEJAQAAAA==.Leviathonian:BAAALgAECgEJAgAAAA==.',
Li='Lightseeker:BAAALgAECgEJAQAAAA==.Lillinna:BAAALgADCgQJBAAAAA==.Lilthina:BAAALgADCgcJBwABLgAECgcJJwAfAF8SAA==.Lisithen:BAAALgADCgEJAQAAAA==.Littlespoon:BAAALgAECgYJCgAAAA==.',
Lo='Loafai:BAABLgAECn80AAQaAAkJ0QvTDAB8AQAaAAgJpwzTDAB8AQAoAAYJ/geaHQCyAAAVAAcJAgQb1QCwAAAAAA==.Lockrocks:BAABLgAECn8lAAIVAAkJYht0IQBXAgAVAAkJYht0IQBXAgAAAA==.Lockycharmz:BAAALgAECgMJAwABLgAECgkJQAAKAMUfAA==.Lorcán:BAAALgAECgYJDwAAAA==.Lormazlezrax:BAACLgAFFH8QAAIfAAQJzROxNAD4AAAfAAQJzROxNAD4AAAuAAQKfyQAAh8ABwltIBUZAE0CAB8ABwltIBUZAE0CAAAA.Lowlife:BAAALgAECggJDAAAAA==.',
Lu='Luis:BAAALgAECgQJBAAAAA==.Lumaron:BAAALgADCgEJAgAAAA==.Lunamizka:BAAALgADCgIJAgAAAA==.Lunella:BAAALgAFFAEJAQAAAA==.Lunethira:BAAALgAECgUJDwABLgAFFAEJAQAIAAAAAA==.Lupe:BAAALgAECgcJBwAAAA==.Lustdeeznuts:BAABLgAECn8XAAIhAAYJjRspNABcAQAhAAYJjRspNABcAQAAAA==.',
Ly='Lylat:BAAALgAECgIJAgAAAA==.',
['Ló']='Lórdelrond:BAAALgAECgIJAgAAAA==.',
['Lú']='Lúpo:BAAALgAECgYJDQAAAA==.',
Ma='Machezemo:BAACLgAFFH8OAAICAAMJohYEcgDtAAACAAMJohYEcgDtAAAuAAQKfyIAAgIACQlyIVgpAG4CAAIACQlyIVgpAG4CAAAA.Madhatter:BAAALgAECgUJBwAAAA==.Mahalka:BAAALgAECgEJAQAAAA==.Maki:BAABLgAECn8kAAIbAAgJeiK/BgD7AgAbAAgJeiK/BgD7AgAAAA==.Malegar:BAAALgADCgkJIQAAAA==.Malendor:BAABLgAECn8zAAIGAAkJmSb4AABwAwAGAAkJmSb4AABwAwAAAA==.Mallaki:BAAALgADCgUJBAAAAA==.Mammajamma:BAAALgAECgEJBAABLgAECgYJCgAIAAAAAA==.Manbearcat:BAAALgAECgYJDQAAAA==.Marcydaghoul:BAAALgADCgUJBQAAAA==.Marivoker:BAAALgAECgUJDQABLgAFFAEJAQAIAAAAAA==.Marsvolta:BAAALgADCgYJBgAAAA==.Maruxus:BAACLgAFFH8FAAIYAAMJDQu7BwDcAAAYAAMJDQu7BwDcAAAuAAQKf0EAAxgACQncHO4BAMkCABgACQncHO4BAMkCAAEABgl+D0wGAGEBAAAA.Marvilla:BAAALgAECgkJEgAAAA==.Marwen:BAAALgAECgUJDgAAAA==.Mathbrew:BAEBLgAECn8mAAIJAAgJ6SFxCgCEAgAJAAgJ6SFxCgCEAgABLgAFFAQJCgAUAKYWAA==.Mathbruh:BAEALgAECgQJBAABLgAFFAQJCgAUAKYWAA==.Maulsin:BAABLgAECn8WAAQaAAgJ7Qq9FgD9AAAaAAYJFgq9FgD9AAAVAAMJZgZ77AB6AAAoAAMJmAupMABSAAAAAA==.',
Mc='Mcchicken:BAAALgADCgIJAgAAAA==.Mcdeathy:BAAALgAECgIJAgABLgAECggJDwAIAAAAAA==.Mclardragos:BAABLgAECn8hAAIMAAkJvhzABQCsAgAMAAkJvhzABQCsAgAAAA==.',
Me='Meatshield:BAAALgAECgQJBwABLgAECgQJBwAIAAAAAA==.Mecharoni:BAAALgAECggJDQABLgAECgkJQQARAPsjAA==.Medreaux:BAAALgAECgkJAgAAAA==.Mehv:BAEALgAECgkJCwAAAQ==.Melindria:BAABLgAECn8iAAMlAAgJjQuBPwA0AQAlAAYJHw+BPwA0AQAgAAgJawR/PgCXAAABLgAECgkJJgAfAJIYAA==.Mendicine:BAABLgAECn8kAAIQAAkJvxoxEADIAgAQAAkJvxoxEADIAgAAAA==.Menmoe:BAAALgAECgEJAQAAAA==.',
Mf='Mfdoom:BAAALgAECgMJAwAAAA==.',
Mi='Miacyn:BAABLgAECn8WAAICAAcJ1AFzAQGgAAACAAcJ1AFzAQGgAAAAAA==.Miladybast:BAABLgAECn8pAAICAAgJnwRTsgAaAQACAAgJnwRTsgAaAQAAAA==.Miniwheet:BAAALgAECgYJDwABLgAECgkJQAAKAMUfAA==.Mirra:BAABLgAECn8hAAIHAAkJGQulUQChAQAHAAkJGQulUQChAQAAAA==.Misha:BAAALgADCgUJBQAAAA==.Missdorei:BAAALgAECgUJCAAAAA==.',
Mo='Mogged:BAABLgAECn8vAAICAAgJlSEiHgCiAgACAAgJlSEiHgCiAgAAAA==.Moistmaker:BAAALgAECgIJBAAAAA==.Mojocity:BAAALgADCgYJCwAAAA==.Molai:BAAALgAECgcJBAAAAA==.Monkdangit:BAAALgAECgYJCQAAAA==.Mordraidas:BAAALgADCgkJCQAAAA==.Morionso:BAABLgAECn8vAAIeAAgJCx05CQAxAgAeAAgJCx05CQAxAgAAAA==.Morphyrinsjr:BAAALgADCgcJEgABLgAECggJKwAHALcbAA==.Mortarion:BAABLgAECn86AAIUAAkJNCEJDwDsAgAUAAkJNCEJDwDsAgAAAA==.Moxxulae:BAAALgADCgkJCAAAAA==.Moõn:BAABLgAECn8pAAIRAAkJTRAuJACzAQARAAkJTRAuJACzAQAAAA==.',
Mu='Murcié:BAABLgAECn8pAAMFAAgJLxakOAASAgAFAAgJLxakOAASAgAOAAYJHwkQOgAZAQAAAA==.Murdiûs:BAABLgAECn8kAAIPAAkJ7RvsEwBrAgAPAAkJ7RvsEwBrAgAAAA==.',
My='Myaliki:BAAALgADCgcJBwABLgAECgUJCQAIAAAAAA==.Myregards:BAAALgAECgMJAwAAAA==.Myspaceshria:BAAALgAECgUJDgABLgAECggJIgAUAFkYAA==.Mythbruh:BAECLgAFFH8KAAIUAAQJphZ7TwBDAQAUAAQJphZ7TwBDAQAuAAQKfyAAAxQACAnAIQYoAFkCABQACAn6IAYoAFkCAAoABwmVIbANACQCAAAA.Mythis:BAAALgAECgMJBAAAAA==.',
['Mó']='Mósh:BAAALgAECgYJBgAAAA==.',
Na='Nahane:BAAALgAECgQJBAAAAA==.Nahlur:BAAALgAECgMJAwAAAA==.Naoko:BAAALgAECgEJAgAAAA==.Natani:BAAALgADCgkJEQAAAA==.Nayrlock:BAACLgAFFH8FAAIVAAMJDhXdbgDVAAAVAAMJDhXdbgDVAAAuAAQKfyoABBUACQkTIEkaALcCABUACQkTIEkaALcCABoABQm1F18RABcBACgABAm4EKRAALIAAAAA.Nayuta:BAAALgADCgYJBQAAAA==.Nazal:BAAALgADCgEJAQABLgADCgEJAQAIAAAAAA==.',
Nc='Nc:BAAALgAECgEJAQAAAA==.Nctee:BAABLgAECn8YAAICAAcJ/BRMiQBeAQACAAcJ/BRMiQBeAQAAAA==.',
Ne='Necrodwarf:BAAALgADCgEJAQAAAA==.Necropally:BAAALgAECgQJCwAAAA==.Necrotizor:BAABLgAECn8kAAMVAAgJzB2MKQAvAgAVAAgJzB2MKQAvAgAoAAEJNBWZOQA4AAAAAA==.Neonsalmandr:BAAALgAECgEJAQAAAA==.Nerfhammer:BAAALgADCgIJBAAAAA==.Nerrol:BAAALgADCgkJCQAAAA==.',
Ni='Nialliv:BAAALgADCgcJCQAAAA==.Nidvin:BAABLgAECn8bAAIfAAYJURx3MwDWAQAfAAYJURx3MwDWAQAAAA==.Nightsmoke:BAAALgAECgQJBQAAAA==.Nixa:BAAALgADCgcJFwAAAA==.',
Nk='Nkb:BAAALgAECgYJDAAAAA==.',
Nn='Nnoitra:BAAALgADCgcJBwAAAA==.',
No='Noceman:BAAALgADCgEJAQAAAA==.Nock:BAAALgAECgkJEAAAAA==.Nogg:BAAALgAECgEJAQAAAA==.Nolanel:BAAALgAECggJDgAAAA==.Noll:BAAALgADCgUJBQAAAA==.Nonattarius:BAAALgAECgYJCwAAAA==.Norezfou:BAABLgAECn8+AAMbAAkJKyBZCwCaAgAbAAkJKyBZCwCaAgAEAAYJgRtRIAC7AQAAAA==.Nornir:BAAALgAECgIJAgAAAA==.Norran:BAABLgAECn8iAAMEAAkJGRumDgBmAgAEAAkJGRumDgBmAgATAAYJvBkzJQCYAQAAAA==.Norvera:BAAALgAECgIJAgAAAA==.Notalice:BAAALgAECgYJBwAAAA==.Notmywife:BAAALgAECgYJDQAAAA==.Novakri:BAAALgADCgUJCAABLgADCgYJDAAIAAAAAA==.',
Nu='Nuker:BAABLgAECn8dAAICAAgJkwdIlwBFAQACAAgJkwdIlwBFAQAAAA==.Nurobi:BAABLgAECn8fAAIlAAgJkhRGKACAAQAlAAgJkhRGKACAAQAAAA==.Nuundix:BAACLgAFFH8GAAIhAAMJnQQDOACcAAAhAAMJnQQDOACcAAAuAAQKfxYAAiEACAmHB29IAAIBACEACAmHB29IAAIBAAAA.',
Ny='Nyri:BAAALgADCgEJAQAAAA==.Nysel:BAAALgAECgkJAQAAAA==.Nysera:BAAALgADCggJCAAAAA==.Nyxy:BAAALgAECgUJDAAAAA==.',
Oc='Ocey:BAAALgAECgUJBgABLgAECgkJGgAQAG4YAA==.',
Od='Odyn:BAABLgAECn8pAAIcAAgJ/RyHJwBaAgAcAAgJ/RyHJwBaAgAAAA==.',
Oo='Ooyu:BAAALgAECgUJCwAAAA==.',
Or='Orangepeel:BAAALgADCgUJBQAAAA==.Oridk:BAACLgAFFH8FAAIUAAIJEA5svQCVAAAUAAIJEA5svQCVAAAuAAQKfxQAAhQACAlNFR+MAGgBABQACAlNFR+MAGgBAAEuAAUUBQkaABYAuSIA.Orimage:BAAALgADCgkJDAABLgAFFAUJGgAWALkiAA==.Oripal:BAAALgAECgcJDAABLgAFFAUJGgAWALkiAA==.Orisham:BAAALgADCgkJCQABLgAFFAUJGgAWALkiAA==.Oríon:BAACLgAFFH8aAAIWAAUJuSJfBwCGAQAWAAUJuSJfBwCGAQAuAAQKfyYAAxYACQkuI7sFALECABYACQkuI7sFALECABcABQlqFgtTAAABAAAA.',
Ou='Outofmyele:BAAALgADCgQJBAAAAA==.',
Ow='Owoker:BAABLgAECn8WAAISAAgJJRqJBgDYAQASAAgJJRqJBgDYAQAAAA==.',
Pa='Pablo:BAABLgAECn8VAAInAAcJ3xl8CwAHAgAnAAcJ3xl8CwAHAgAAAA==.Pancaked:BAAALgAECgEJAQABLgAFFAYJIgADAD8mAA==.Pancakedup:BAAALgAECgcJDAABLgAFFAYJIgADAD8mAA==.Pandozer:BAAALgAECggJEgAAAA==.Pankratos:BAABLgAECn8WAAMJAAkJliOyFABoAgAJAAkJliOyFABoAgAGAAMJLyBYPgD4AAAAAA==.Papaspud:BAABLgAECn8zAAIbAAkJ3A8uIwCcAQAbAAkJ3A8uIwCcAQAAAA==.Paradias:BAACLgAFFH8dAAIZAAYJ0BmkCgDEAQAZAAYJ0BmkCgDEAQAuAAQKfzAAAxkACAm2IPYMAMoCABkACAmaIPYMAMoCABgABgmxFzEMAGIBAAAA.Pastor:BAABLgAECn8UAAMmAAYJTQMYPQBvAAAmAAUJjAMYPQBvAAAjAAEJVQLGgwAMAAAAAA==.Patpat:BAAALgADCgcJBgAAAA==.Paxxfist:BAABLgAECn8iAAIPAAgJ+RIVLQCzAQAPAAgJ+RIVLQCzAQAAAA==.',
Pe='Peachdevil:BAAALgAECgEJAQAAAA==.Pecorino:BAAALgAECgcJAQABLgAECgcJBwAIAAAAAA==.Penryn:BAAALgAECgEJAQAAAA==.Pentive:BAACLgAFFH8JAAInAAMJeiCrCAAUAQAnAAMJeiCrCAAUAQAuAAQKfxsAAicACAljHDkFAL0CACcACAljHDkFAL0CAAAA.Peppersgotem:BAAALgAECgEJAQAAAA==.Peppersham:BAABLgAECn8rAAMhAAgJ5xzyHgDeAQAhAAcJwBvyHgDeAQAfAAMJGxUVgQCPAAAAAA==.Peppersmonk:BAAALgAECgQJBgAAAA==.Pepromene:BAAALgADCgUJBQAAAA==.Perff:BAAALgADCgYJBQAAAA==.Perhaps:BAACLgAFFH8MAAIJAAMJryPnGwA4AQAJAAMJryPnGwA4AQAuAAQKfxwAAgkACAkbIokHAA0DAAkACAkbIokHAA0DAAAA.Persephone:BAAALgADCgYJBgAAAA==.Petesdragin:BAABLgAECn8oAAIMAAgJGRRlDQDyAQAMAAgJGRRlDQDyAQAAAA==.',
Pf='Pfftpfft:BAABLgAECn8bAAIHAAgJVh7/HwBcAgAHAAgJVh7/HwBcAgAAAA==.',
Ph='Phatdanny:BAABLgAECn8VAAIcAAgJcBg7VwC7AQAcAAgJcBg7VwC7AQAAAA==.Phatdumpy:BAABLgAECn8mAAQWAAkJwRAlGQDSAQAWAAkJbA0lGQDSAQAHAAcJcRO0OgDEAQAXAAQJ7wr/XADOAAAAAA==.Phattphatt:BAABLgAECn8bAAInAAcJEBqbDwCrAQAnAAcJEBqbDwCrAQAAAA==.Phonycheese:BAABLgAECn8UAAMcAAgJkQ5NpgA0AQAcAAYJORNNpgA0AQAkAAMJuRfZawB3AAAAAA==.Phur:BAABLgAFFH8NAAIjAAMJeB8SGgACAQAjAAMJeB8SGgACAQAAAA==.',
Pi='Pinbal:BAAALgAECgQJBAAAAA==.Pixen:BAACLgAFFH8FAAIVAAMJcAkSgAC0AAAVAAMJcAkSgAC0AAAuAAQKf0UAAhUACQn8GwITALACABUACQn8GwITALACAAAA.',
Pl='Plagueiss:BAABLgAECn8cAAIUAAgJjhrPPABEAgAUAAgJjhrPPABEAgAAAA==.',
Po='Pocalypse:BAAALgAECgYJBQAAAA==.Pocketsand:BAAALgAECgUJBwAAAA==.Poisònivy:BAAALgAECgUJBQAAAA==.Ponkeylips:BAACLgAFFH8SAAILAAUJBh5nFABWAQALAAUJBh5nFABWAQAuAAQKfx0AAwsACAmWIO0MAJUCAAsACAmWIO0MAJUCACMAAQnNBsNDADEAAAAA.Portstar:BAABLgAECn8hAAMCAAkJbAuocACTAQACAAkJTgmocACTAQAdAAYJzQ2hDgDZAAAAAA==.Powwerbottom:BAAALgADCgIJBAAAAA==.',
Pr='Precast:BAAALgADCgUJCgAAAA==.Prestoresto:BAAALgAECgEJAQAAAA==.Prieske:BAABLgAECn8rAAQTAAcJ3R2dEgBCAgATAAcJQB2dEgBCAgAbAAUJ+RmUSAAXAQAEAAQJtBcKPwAMAQAAAA==.Primed:BAABLgAECn9GAAInAAkJ9BYxCQAkAgAnAAkJ9BYxCQAkAgAAAA==.Privm:BAABLgAFFH8KAAIPAAUJ0QghKAAAAQAPAAUJ0QghKAAAAQAAAA==.Privxd:BAABLgAFFH8IAAIQAAQJwBj8CQA5AQAQAAQJwBj8CQA5AQAAAA==.Prunesa:BAAALgADCgcJBQAAAA==.',
Pu='Pungla:BAAALgAECggJDwAAAA==.',
['Pî']='Pîper:BAAALgADCgYJBwAAAA==.',
['Pï']='Pït:BAAALgAECggJEAAAAA==.',
Qp='Qprawindfury:BAAALgAECgYJEwAAAA==.',
Qu='Quadtwat:BAAALgAECgQJBwAAAA==.Quahogger:BAAALgAECgYJEQAAAA==.Quazer:BAAALgAECgEJAgAAAA==.Quelthanos:BAAALgAECgUJBQAAAA==.',
Ra='Radical:BAAALgAECgkJDgAAAA==.Railyard:BAAALgADCgMJAwABLgAECgIJAgAIAAAAAA==.Raivn:BAAALgADCgEJAQAAAA==.Rajasta:BAAALgAECgQJCQAAAA==.Rajkwit:BAAALgADCgcJCwAAAA==.Rajzova:BAAALgADCgcJCgABLgAECgkJJAAYAEMLAA==.Randomclown:BAAALgAECgYJCgAAAA==.Rapi:BAAALgAECgMJAwAAAA==.Rascalfats:BAABLgAECn8cAAICAAcJYg/ekQBOAQACAAcJYg/ekQBOAQAAAA==.Rashii:BAABLgAECn8ZAAIbAAkJ4BV6FQAZAgAbAAkJ4BV6FQAZAgAAAA==.Rawor:BAABLgAECn8qAAMaAAgJnRb4BwDbAQAaAAgJMRX4BwDbAQAVAAcJSBLscgBPAQAAAA==.',
Re='Rebaderchi:BAACLgAFFH8VAAIFAAUJ1A1ySAACAQAFAAUJ1A1ySAACAQAuAAQKfzQAAgUACQktHYgcAF8CAAUACQktHYgcAF8CAAAA.Relyne:BAAALgADCgYJBgAAAA==.Remo:BAAALgAECgMJAwAAAA==.Remoria:BAAALgAECgkJDAAAAA==.Rendaye:BAAALgAFFAEJAgAAAA==.Renildan:BAAALgAECgYJDwAAAA==.Renscope:BAAALgAECgcJAQAAAA==.Resala:BAAALgADCgYJBgAAAA==.Rev:BAAALgADCgMJAwAAAA==.Revanhawk:BAAALgADCgkJEQAAAA==.Revna:BAAALgADCgcJBwAAAA==.Rezputan:BAACLgAFFH8KAAMpAAMJnhPnEgDVAAApAAMJtxLnEgDVAAAUAAIJJA8/1wCEAAAuAAQKfyMAAykACQmJH08DAKcCACkACQmOHk8DAKcCABQACAmJGPxUAL4BAAAA.',
Rh='Rhohorn:BAAALgAECgUJBwAAAA==.Rholand:BAABLgAECn8gAAMLAAgJgx9HFgA2AgALAAgJgx9HFgA2AgAmAAQJNReQOgB7AAAAAA==.Rhovid:BAAALgAECgEJAgAAAA==.',
Ri='Rind:BAAALgAECgYJCQAAAA==.Rioken:BAABLgAECn8hAAMVAAkJmhfgMAAPAgAVAAkJmhfgMAAPAgAoAAEJgxCAbgA4AAAAAA==.Riolobo:BAAALgADCggJCAAAAA==.Riorage:BAABLgAECn8mAAIfAAgJpxgXIwAuAgAfAAgJpxgXIwAuAgAAAA==.Ritz:BAAALgAECgEJAQAAAA==.Rizzoy:BAACLgAFFH8IAAILAAMJORPMLwDdAAALAAMJORPMLwDdAAAuAAQKf0MAAgsACQmVHjQKALkCAAsACQmVHjQKALkCAAAA.',
Ro='Rohoth:BAAALgAECgMJBQAAAA==.Rolaiya:BAAALgADCgYJBgAAAA==.Rolleasy:BAECLgAFFH8TAAIPAAYJCyaUBQCUAgAPAAYJCyaUBQCUAgAuAAQKfykAAg8ABwmiJdQPAJQCAA8ABwmiJdQPAJQCAAAA.Rollo:BAAALgAECgUJDgAAAA==.Rolor:BAAALgADCgYJBgAAAA==.Rookiefister:BAAALgAECgQJAwAAAA==.Rovyr:BAABLgAECn8+AAQMAAkJHiLZAQBnAwAMAAkJHiLZAQBnAwARAAMJXwsTcQB3AAASAAEJuAHmRQAeAAAAAA==.',
Ru='Ruckabis:BAABLgAECn8iAAMfAAkJex/dGwBgAgAfAAkJex/dGwBgAgAhAAEJSwctpwAnAAAAAA==.Rundeezyy:BAAALgADCgYJCQAAAA==.',
Ry='Ryllock:BAAALgAECgIJAgAAAA==.Rylos:BAACLgAFFH8HAAIUAAMJ5AYiowDDAAAUAAMJ5AYiowDDAAAuAAQKfx8AAhQACQlaDr1SAMQBABQACQlaDr1SAMQBAAAA.Rytotem:BAAALgAECgQJCwAAAA==.Ryumi:BAAALgADCgkJCwAAAA==.Ryvington:BAAALgAECggJCAAAAA==.Ryvmonk:BAAALgADCgEJAQAAAA==.',
Sa='Saansula:BAAALgAECgUJDQAAAA==.Sabian:BAABLgAECn8iAAIlAAkJzhLMHQDNAQAlAAkJzhLMHQDNAQAAAA==.Saintjeb:BAACLgAFFH8FAAIeAAIJ5AxcEABuAAAeAAIJ5AxcEABuAAAuAAQKfxQAAh4ACAkDEtgXAFgBAB4ACAkDEtgXAFgBAAEuAAUUAwkEAAgAAAAA.Saitami:BAAALgAECgEJAQAAAA==.Saitamå:BAAALgAECgYJDAAAAA==.Sakisan:BAAALgAECgEJAgAAAA==.Salinity:BAABLgAECn8nAAMVAAkJmCIiCAAQAwAVAAkJXCIiCAAQAwAoAAcJRSBvBwBRAgAAAA==.Samanaras:BAABLgAECn8VAAIjAAgJHBBWHgBfAQAjAAgJHBBWHgBfAQAAAA==.Sanari:BAAALgADCgMJAwAAAA==.Sancarlos:BAAALgAECgIJAgABLgAECgcJDQAIAAAAAA==.Sangwyn:BAAALgAECgUJBQABLgAECggJJAAbAHoiAA==.Santiago:BAAALgAECgYJDwAAAA==.Saratoga:BAABLgAECn8YAAIcAAcJexoJXgDJAQAcAAcJexoJXgDJAQAAAA==.Sarkana:BAABLgAECn8kAAIkAAkJfB4tCgDfAgAkAAkJfB4tCgDfAgAAAA==.Sarticor:BAAALgAECgEJAQAAAA==.Sassquatch:BAACLgAFFH8FAAIUAAIJVQ6jvgCUAAAUAAIJVQ6jvgCUAAAuAAQKfyQAAxQABwlLGrtXALYBABQABwlLGrtXALYBAAoAAQkgBWteACMAAAAA.Satu:BAAALgAECgEJAQAAAA==.Saxonn:BAACLgAFFH8GAAIhAAIJFgMkRgBkAAAhAAIJFgMkRgBkAAAuAAQKfygAAyEACAn7Deg5AD8BACEACAn7Deg5AD8BAB8AAwlpAzmIAHMAAAAA.Saydis:BAABLgAECn8ZAAIHAAgJMghaeQA/AQAHAAgJMghaeQA/AQAAAA==.',
Sc='Schuftt:BAABLgAECn8UAAMdAAgJExpxBACjAQAdAAgJExpxBACjAQAiAAEJ9BQODgBGAAAAAA==.',
Se='Seafoodtower:BAAALgAECgEJAQAAAA==.Sebattan:BAAALgAECgcJEwAAAA==.Seleine:BAAALgAECgEJAQABLgAECgkJQAACAEAbAA==.Sello:BAAALgAECgEJAgAAAA==.Seltzers:BAAALgADCgQJCgAAAA==.Selunella:BAAALgADCgEJAQABLgAFFAEJAQAIAAAAAA==.Selvester:BAABLgAECn8lAAIJAAgJDiXTBQDZAgAJAAgJDiXTBQDZAgAAAA==.Senadria:BAABLgAECn8bAAIFAAUJtAppuwCkAAAFAAUJtAppuwCkAAAAAA==.Senseishifu:BAACLgAFFH8IAAIJAAQJBgxALADtAAAJAAQJBgxALADtAAAuAAQKfyEAAgkACQk8F/wQACkCAAkACQk8F/wQACkCAAAA.Seorsen:BAAALgADCgcJEAAAAA==.Servinghunt:BAAALgAECgYJDAAAAA==.Sevalandre:BAAALgAECgEJAgABLgAECggJIgAUAFkYAA==.',
Sh='Shadowskyz:BAAALgADCgYJBgABLgAFFAUJEQADAFUNAA==.Shamatrest:BAAALgAECgEJAwABLgAECgkJKAAUAN4kAA==.Shamina:BAACLgAFFH8RAAIDAAUJVQ0tCQAbAQADAAUJVQ0tCQAbAQAuAAQKfx0AAgMACAmHGSgKAAsCAAMACAmHGSgKAAsCAAAA.Shamite:BAAALgAECgMJAwABLgAECgkJEAAIAAAAAA==.Shammalin:BAABLgAECn8iAAMhAAgJ1AtMQAAiAQAhAAgJ1AtMQAAiAQAfAAUJlgx1fADZAAAAAA==.Shamminator:BAAALgADCgMJAwAAAA==.Shamorex:BAABLgAECn89AAIhAAgJsRrNFgAhAgAhAAgJsRrNFgAhAgAAAA==.Shanoth:BAABLgAECn8XAAMMAAgJ2gOMHgD6AAAMAAgJ2gOMHgD6AAASAAYJ6ggkEgDaAAABLgAECggJIgAUAFkYAA==.Sharkbones:BAAALgAECgEJAQAAAA==.Shatter:BAAALgAECgcJDwAAAA==.Shax:BAAALgAECgUJBgABLgAECgkJJwAVAJgiAA==.Shiftshappen:BAAALgAECgYJCAAAAA==.Shiftyy:BAAALgAECgcJDAAAAA==.Shogun:BAAALgADCgQJCAAAAA==.Shoopywoopy:BAAALgAECgEJAQAAAA==.Shteph:BAAALgAECgYJDAAAAA==.',
Si='Siaerosia:BAAALgADCgEJAQAAAA==.',
Sk='Skaarr:BAABLgAECn8VAAILAAgJ3wgySgAUAQALAAgJ3wgySgAUAQAAAA==.',
Sl='Slayn:BAABLgAECn8lAAICAAgJtxHkaQChAQACAAgJtxHkaQChAQAAAA==.Sleinx:BAAALgADCgMJAwABLgAFFAYJFAAhAGQcAA==.Slowhealsboi:BAAALgAECgQJBAAAAA==.Slushpuppie:BAAALgADCgYJBgAAAA==.Slyrak:BAABLgAECn8yAAMSAAkJfhvJAgB5AgASAAkJfhvJAgB5AgAMAAMJoQgSMQBbAAAAAA==.Slyva:BAAALgAECgMJAwAAAA==.',
Sm='Smithbruh:BAEALgAECgQJBAABLgAFFAQJCgAUAKYWAA==.Smitus:BAAALgAECggJDQAAAA==.Smokescale:BAAALgADCgcJCAAAAA==.',
Sn='Snackie:BAABLgAECn8lAAIfAAgJih6HEgCuAgAfAAgJih6HEgCuAgAAAA==.Sneakyjewel:BAAALgADCgkJEAAAAA==.Snotpig:BAAALgAECggJBwAAAA==.',
So='Solarious:BAAALgAECgEJAQAAAA==.Sorscrasus:BAAALgADCgUJCAAAAA==.Soulcolektor:BAAALgADCgcJDwAAAA==.Souled:BAAALgAECgQJBQAAAA==.Soulreaver:BAAALgADCgcJBwAAAA==.Sourpunchkid:BAAALgADCgQJBAAAAA==.',
Sp='Sparroh:BAAALgADCgEJAQAAAA==.Spikedriver:BAABLgAECn8kAAIHAAkJJxAtTgCrAQAHAAkJJxAtTgCrAQAAAA==.Spradwurd:BAAALgAECgUJCAAAAA==.',
Sq='Squee:BAABLgAECn8UAAMGAAgJuBVwLgBDAQAGAAgJuBVwLgBDAQAJAAEJ1wF4mQAaAAABLgAECggJFAAGALgVAA==.',
St='Stantonio:BAABLgAECn8YAAIdAAkJ+wxYBQB4AQAdAAkJ+wxYBQB4AQAAAA==.Stariane:BAABLgAECn8jAAIOAAkJeh17CwBgAgAOAAkJeh17CwBgAgAAAA==.Startaster:BAAALgAFFAEJAQAAAA==.Starvoid:BAAALgAECgEJAQAAAA==.Steaktartare:BAABLgAECn8lAAIkAAcJiA72OwBMAQAkAAcJiA72OwBMAQAAAA==.Steeldk:BAAALgAECgQJBQAAAA==.Steelfist:BAAALgAECgYJCgAAAA==.Steelpunch:BAAALgAECgUJCAAAAA==.Steelwill:BAAALgAECgIJAwAAAA==.Stonii:BAAALgAECgEJAQAAAA==.Stony:BAABLgAECn8uAAIHAAgJeyOJFQCdAgAHAAgJeyOJFQCdAgAAAA==.Stonyy:BAAALgAECgYJCwAAAA==.Stratpanda:BAAALgAECgEJAQAAAA==.Strelizia:BAAALgAECgIJAgAAAA==.Stressful:BAAALgADCgQJBAAAAA==.',
Su='Sub:BAABLgAFFH8GAAIBAAQJrQXzBwDvAAABAAQJrQXzBwDvAAABLgAFFAYJIgADAD8mAA==.Suetekh:BAAALgADCgUJBQAAAA==.Sukidaiyo:BAABLgAECn8VAAIpAAgJQhaWCgDCAQApAAgJQhaWCgDCAQAAAA==.Summers:BAAALgAECgYJDwAAAA==.Sumonmyface:BAAALgAECgYJEAABLgAECgkJJgAWAMEQAA==.Sunshield:BAAALgAECgMJAwAAAA==.Superillbomb:BAAALgADCgcJDQAAAA==.Superold:BAAALgAECggJCAAAAA==.Suraug:BAAALgADCgcJBwAAAA==.Suzakku:BAAALgAECgQJBQAAAA==.',
Sw='Swampraught:BAABLgAECn8nAAMVAAgJ8Be6PwDYAQAVAAgJ8Be6PwDYAQAoAAEJtA2ocAA1AAAAAA==.',
Sy='Syd:BAAALgADCgYJBgAAAA==.Syletage:BAAALgAECgQJCAAAAA==.Synd:BAAALgADCgEJAQAAAA==.Synrae:BAAALgAECggJBwAAAA==.Syral:BAAALgAECgUJDAAAAA==.Syrion:BAAALgAECgQJBAAAAA==.Sythrane:BAAALgAECgYJCgAAAA==.',
Ta='Taarii:BAAALgADCggJCAAAAA==.Talisoudwave:BAAALgAECgYJDQABLgAECggJIAAQABElAA==.Talomeo:BAAALgAECgIJAgAAAA==.Taradan:BAAALgAECgEJAQAAAA==.Taraxus:BAAALgADCggJDAAAAA==.Tateraider:BAABLgAECn80AAMmAAkJvx0QCABwAgAmAAkJvx0QCABwAgALAAEJQwuzngAxAAAAAA==.Taterknight:BAAALgADCgkJCQAAAA==.Taurnator:BAAALgAECgMJBAAAAA==.Taylorswift:BAAALgAECgMJBgAAAA==.Tayven:BAAALgADCgEJAQAAAA==.',
Te='Tednougat:BAAALgADCgYJBgAAAA==.Telain:BAACLgAFFH8IAAMkAAIJwRcbNACSAAAkAAIJwRcbNACSAAAcAAIJNwvDhgCLAAAuAAQKf1MABCQACQlsF2MUAGECACQACQlsF2MUAGECABwABwnZFpRkAJwBAB4AAgmHFgw3AHUAAAAA.Tensuki:BAAALgAECgMJAwAAAA==.Teslah:BAAALgADCgQJBAAAAA==.',
Th='Thakilla:BAACLgAFFH8MAAIlAAMJcgmPMQCkAAAlAAMJcgmPMQCkAAAuAAQKfzUAAiUACQnOFYkVABgCACUACQnOFYkVABgCAAAA.Thanosonmage:BAAALgADCgcJBwAAAA==.Thavik:BAAALgADCgEJAwAAAA==.Theolodin:BAAALgAECgkJEQAAAA==.Thordrik:BAABLgAECn8UAAMKAAYJFA+IOACnAAAUAAUJ3w2y4gDFAAAKAAUJrguIOACnAAAAAA==.Thorix:BAABLgAECn8ZAAIOAAkJGxQHEwDvAQAOAAkJGxQHEwDvAQAAAA==.Thotmir:BAAALgAECgMJAwAAAA==.Thícc:BAAALgADCgkJCgAAAA==.',
Ti='Tigerburn:BAAALgADCgkJCgAAAA==.Tikibiki:BAAALgADCgMJAwAAAA==.Timbereses:BAAALgADCgUJBQAAAA==.Timberreaper:BAAALgAECgQJDAAAAA==.Tinyz:BAABLgAECn8fAAQbAAcJthUsHwC7AQAbAAcJthUsHwC7AQAEAAUJTwZwWgCeAAATAAEJQhMabgA6AAAAAA==.',
To='Tolua:BAAALgAECgUJCAAAAA==.Tonata:BAABLgAECn8aAAMRAAkJBQsDQwASAQARAAkJBQsDQwASAQAMAAgJlQ2BHAARAQAAAA==.Tonythetiger:BAAALgAECgEJAQABLgAECgkJQAAKAMUfAA==.Tootsie:BAAALgADCgYJEAAAAA==.Tormentus:BAAALgAECgMJAwAAAA==.',
Tr='Trampadin:BAAALgADCgkJCQAAAA==.Trenton:BAAALgADCgUJBwAAAA==.Trexlot:BAAALgAECgIJBgAAAA==.Trinjal:BAABLgAECn8wAAMPAAkJFRukEQCBAgAPAAkJFRukEQCBAgAGAAQJgxvMPwDyAAAAAA==.Trishift:BAAALgAECgQJCgAAAA==.Trueshru:BAAALgAECgIJAwAAAA==.',
Tu='Tubular:BAAALgAECgMJBQAAAA==.Tuskadin:BAACLgAFFH8JAAIcAAQJLRscNwAuAQAcAAQJLRscNwAuAQAuAAQKfyoAAhwACAlFJK4bAMQCABwACAlFJK4bAMQCAAAA.',
Tw='Tweeq:BAAALgAECgQJCgAAAA==.',
Ty='Tyjan:BAABLgAECn8XAAIcAAcJYgc4wgD5AAAcAAcJYgc4wgD5AAAAAA==.Tyrana:BAAALgAECgMJAwAAAA==.Tyriq:BAAALgADCgYJBgAAAA==.',
['Tã']='Tãz:BAAALgAECgEJAgAAAA==.',
Ul='Ulra:BAAALgADCgkJCgAAAA==.',
Un='Unclothed:BAABLgAECn8cAAInAAcJlwtuHgACAQAnAAcJlwtuHgACAQAAAA==.Unicorn:BAAALgADCggJCgAAAA==.Untòld:BAAALgADCggJCAABLgAECgcJHAACAJ4QAA==.',
Va='Valentine:BAAALgADCgIJAgAAAA==.Valitymage:BAAALgADCgEJAQAAAA==.Varthios:BAAALgAECgEJBAAAAA==.Varyusha:BAAALgAECgMJBQAAAA==.',
Ve='Velene:BAAALgADCgEJAQABLgAECgkJQAACAEAbAA==.Venzallow:BAAALgAECgUJBwAAAA==.Veralynn:BAAALgADCgcJBwAAAA==.Veravibes:BAAALgAECgQJCwAAAA==.Vermagnus:BAABLgAECn8lAAMJAAgJXh1GDgBKAgAJAAgJXh1GDgBKAgAGAAEJyA5kkQA0AAAAAA==.Vespor:BAABLgAECn8ZAAIQAAYJHR/ZJwAIAgAQAAYJHR/ZJwAIAgAAAA==.',
Vi='Viktorya:BAABLgAECn8iAAIMAAcJJBedFgDlAQAMAAcJJBedFgDlAQAAAA==.Vilelyn:BAABLgAECn8lAAMGAAgJbReNGADiAQAGAAgJbReNGADiAQAPAAIJURKZhwBsAAABLgAECggJKwAcAHobAA==.Viloria:BAABLgAECn8qAAIgAAgJOxQ7FwCFAQAgAAgJOxQ7FwCFAQAAAA==.Vincent:BAAALgAECgQJCAAAAA==.Virrard:BAACLgAFFH8IAAIHAAIJEBkWbACnAAAHAAIJEBkWbACnAAAuAAQKfy8AAwcACQmFG4ohAFQCAAcACQmFG4ohAFQCABcAAglgD6B1AGgAAAAA.Vitalyellow:BAAALgADCgYJBgAAAA==.',
Vl='Vladimor:BAABLgAECn8WAAIVAAcJZxnMcABUAQAVAAcJZxnMcABUAQAAAA==.Vladimyrr:BAABLgAECn8bAAMcAAkJERaYWwCwAQAcAAkJERaYWwCwAQAeAAEJugX1VwAVAAAAAA==.',
Vo='Vodan:BAAALgADCgEJAQAAAA==.Voidplague:BAAALgAECgYJDQAAAA==.Voidscarred:BAAALgAECgQJEgAAAA==.Vozrezz:BAABLgAECn8oAAMGAAgJxCHICACuAgAGAAgJxCHICACuAgAJAAYJlBwyIQCWAQAAAA==.',
Vu='Vualake:BAAALgADCgcJDgAAAA==.',
Vy='Vyridian:BAAALgAECgQJAwABLgAECgYJEwAIAAAAAA==.',
['Vë']='Vëda:BAABLgAECn8kAAIbAAkJKxEFHwC9AQAbAAkJKxEFHwC9AQAAAA==.',
Wa='Wardragon:BAAALgADCgcJCwAAAA==.Warrwras:BAAALgADCgcJDgAAAA==.Wasical:BAAALgAECgQJBAAAAA==.',
Wh='Wheaties:BAAALgAECgcJDAABLgAECgkJQAAKAMUfAA==.',
Wi='Wicker:BAABLgAECn8vAAIgAAkJ/SEbBADPAgAgAAkJ/SEbBADPAgAAAA==.Wickievoker:BAAALgADCgkJCQABLgAECgkJLwAgAP0hAA==.Wintersprout:BAAALgADCgYJBgAAAA==.Wintin:BAAALgAECgEJAgAAAA==.Wiskey:BAAALgAECgYJCQAAAA==.Wiçker:BAAALgAECgYJDAABLgAECgkJLwAgAP0hAA==.',
Wo='Wolford:BAABLgAECn8aAAIQAAcJKht4KgD5AQAQAAcJKht4KgD5AQAAAA==.Woogie:BAAALgADCgYJCgAAAA==.Wordz:BAAALgAECgEJAgAAAA==.',
Wr='Wras:BAABLgAECn8qAAIKAAgJDyAJCQB7AgAKAAgJDyAJCQB7AgAAAA==.Wretched:BAAALgAECgcJBQAAAA==.',
Wy='Wyrnn:BAAALgADCgcJEAAAAA==.Wysstical:BAAALgAECgcJBwABLgAFFAYJIgADAD8mAA==.',
['Wò']='Wòbbles:BAABLgAECn8WAAIcAAcJPROlewBsAQAcAAcJPROlewBsAQABLgAECgcJHAACAGIPAA==.',
Xa='Xalnova:BAAALgADCgYJDAAAAA==.Xandos:BAAALgAECgUJCgAAAA==.Xandrah:BAABLgAECn8iAAIEAAgJmQiJNwAuAQAEAAgJmQiJNwAuAQAAAA==.Xanslash:BAABLgAECn8jAAIFAAkJwR08HQBaAgAFAAkJwR08HQBaAgAAAA==.Xari:BAACLgAFFH8fAAICAAgJVBZTEQBFAgACAAgJVBZTEQBFAgAuAAQKfywAAgIACQl1IwcSADsDAAIACQl1IwcSADsDAAAA.',
Xh='Xhalo:BAAALgADCggJCAAAAA==.',
Xi='Xiansai:BAABLgAECn8fAAIEAAkJbxblGwDfAQAEAAkJbxblGwDfAQAAAA==.Xiongwei:BAAALgAECgEJAgAAAA==.',
Ya='Yappey:BAACLgAFFH8GAAIJAAIJxx1EPQCjAAAJAAIJxx1EPQCjAAAuAAQKfx8AAgkACAkXIv0IAJoCAAkACAkXIv0IAJoCAAAA.',
Ye='Yehni:BAACLgAFFH8FAAIbAAMJKSOwEgAdAQAbAAMJKSOwEgAdAQAuAAQKf0wAAxsACQmtJLwCAGkDABsACQmtJLwCAGkDAAQABgncHGQiAKwBAAAA.',
Yo='Youthinasia:BAAALgAECgQJBAAAAA==.',
Ys='Ys:BAAALgAECgIJAgABLgAECgkJJAAbACsRAA==.',
Yu='Yurasick:BAAALgAECgcJCgAAAA==.',
Za='Zaesha:BAAALgAECgMJAwAAAA==.Zalarii:BAAALgADCgEJAgAAAA==.Zarox:BAABLgAECn8eAAIUAAkJJBLmVAC+AQAUAAkJJBLmVAC+AQAAAA==.',
Ze='Zerega:BAAALgAECgQJBQABLgAECgkJJAAYAEMLAA==.Zeroelement:BAABLgAECn8WAAIkAAgJPB+oMgCAAQAkAAgJPB+oMgCAAQAAAA==.',
Zi='Zimgir:BAAALgADCgEJAQAAAA==.',
Zo='Zombiehippo:BAABLgAECn8sAAICAAkJTBtXLABhAgACAAkJTBtXLABhAgAAAA==.Zorcons:BAAALgAECgEJAQAAAA==.',
Zu='Zuuzuu:BAAALgADCgEJAQAAAA==.',
['Áu']='Áutarch:BAABLgAECn8ZAAILAAgJYgp9PwA+AQALAAgJYgp9PwA+AQAAAA==.',
['Èl']='Èlty:BAAALgAECgMJAwAAAA==.',
['Ðe']='Ðemøn:BAABLgAECn8VAAIOAAYJ5BYrIgBUAQAOAAYJ5BYrIgBUAQAAAA==.',
['Ðr']='Ðrexy:BAAALgADCgUJBQAAAA==.',
['Øg']='Øgar:BAAALgAECgMJBAAAAA==.',
['ßa']='ßambi:BAAALgAECgIJAQAAAA==.',
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
