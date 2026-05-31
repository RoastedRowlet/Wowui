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

local lookup = {'Mage-Frost','Shaman-Enhancement','Priest-Shadow','DemonHunter-Devourer','Monk-Windwalker','Hunter-BeastMastery','Unknown-Unknown','Monk-Brewmaster','DeathKnight-Blood','Warrior-Fury','Evoker-Preservation','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Mistweaver','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Priest-Discipline','Warlock-Demonology','Hunter-Survival','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Warlock-Affliction','DeathKnight-Unholy','Priest-Holy','Paladin-Retribution','Mage-Arcane','Paladin-Protection','Shaman-Restoration','Druid-Guardian','Shaman-Elemental','Mage-Fire','Warrior-Arms','Paladin-Holy','Druid-Balance','Warrior-Protection','Druid-Feral','Warlock-Destruction','Rogue-Outlaw','DeathKnight-Frost',}
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=46,date='2026-05-30',data={Ac='Acense:BAAALgAECgYJDAAAAA==.Acesham:BAAALgAECgEJAQAAAA==.Acewing:BAAALgADCgkJCgAAAA==.Acidlock:BAAALgAECgEJAgAAAA==.Acidpriest:BAAALgAECggJDgAAAA==.Acidshaman:BAAALgADCgYJBwAAAA==.',
Ad='Adacey:BAAALgAECgcJDgAAAA==.Ademeo:BAAALgAFFAEJAQABLgAFFAYJIQABAOkUAA==.Adragon:BAAALgAECgcJDQAAAA==.Adrenalized:BAAALgAECgIJAgAAAA==.',
Ae='Aedryll:BAAALgAECgYJDQAAAA==.Aeriden:BAAALgAECgEJAQAAAA==.Aesuga:BAABLgAECn9EAAICAAkJEiZpAABpAwACAAkJEiZpAABpAwAAAA==.Aethelflaed:BAABLgAECn8tAAIDAAcJcxyWGADmAQADAAcJcxyWGADmAQAAAA==.',
Ag='Agnolotti:BAAALgAECgUJCAAAAA==.',
Ai='Aimedjupiter:BAAALgAECgYJEQABLgAFFAUJDwAEAMUYAA==.Air:BAAALgADCgcJBwABLgAECgkJGQAFAGoZAA==.Airlyn:BAABLgAECn8gAAIGAAcJLQsbbwBLAQAGAAcJLQsbbwBLAQAAAA==.Aisen:BAAALgADCgEJAQABLgAECgEJAQAHAAAAAA==.',
Ak='Aktras:BAAALgAECgUJDwAAAA==.',
Al='Alaunu:BAAALgAECgUJBQABLgAECgkJJwAIAPMIAA==.Aleas:BAAALgAECgQJCQAAAA==.Aliciab:BAAALgADCgYJEAAAAA==.Alkaid:BAAALgAECgEJAQAAAA==.Alndvia:BAAALgAECgcJEwAAAA==.Alponkster:BAAALgADCggJEwAAAA==.Alunia:BAAALgAECgQJCQAAAA==.Alytheal:BAAALgAECgEJAQABLgAECgkJIgAJAHAdAA==.',
Am='Americow:BAAALgAECgIJAgAAAA==.',
An='Anarky:BAABLgAECn8sAAIKAAgJ4ANaUQDsAAAKAAgJ4ANaUQDsAAAAAA==.Andarnah:BAAALgADCgQJBAAAAA==.Annebonny:BAAALgADCgkJCQAAAA==.Annunaki:BAAALgAECgIJAwAAAA==.Anthrfinpete:BAAALgAECgYJDQABLgAECgcJJgALAPcVAA==.Anze:BAAALgAECgIJAgAAAA==.',
Ar='Arathenes:BAAALgADCgcJCQAAAA==.Araylen:BAAALgADCgEJAQAAAA==.Archae:BAAALgAECgEJAQAAAA==.Archdemon:BAABLgAECn8kAAMMAAkJABhrCQC5AQAMAAkJABhrCQC5AQANAAEJWRt5ZQBOAAAAAA==.Ariannette:BAAALgAECgMJAwAAAA==.Arilyn:BAAALgADCgMJAwAAAA==.Arkhanx:BAAALgAECgUJDAAAAA==.Artemisia:BAAALgAECgQJCAAAAA==.Artichoke:BAABLgAECn8cAAMNAAkJHhBVJgAiAQANAAcJohJVJgAiAQAEAAUJTAdjsQCjAAAAAA==.',
As='Ashamane:BAAALgAECgMJAwABLgAECgUJDAAHAAAAAA==.Ashanara:BAAALgADCgEJAQABLgAECggJKwAOAFYaAA==.Asheril:BAAALgAECgQJBQAAAA==.Ashy:BAAALgADCgUJBQAAAA==.Astrov:BAACLgAFFH8FAAINAAIJMw0VHACBAAANAAIJMw0VHACBAAAuAAQKfxsAAw0ACQmfE2gSAOgBAA0ACQmfE2gSAOgBAAQABQmEDLqnAMEAAAAA.',
At='Athera:BAAALgADCggJCAAAAA==.',
Au='Auani:BAABLgAECn8wAAIPAAkJhCM7AwCFAwAPAAkJhCM7AwCFAwAAAA==.Augtistic:BAABLgAECn9BAAMQAAkJ+yOhAwAiAwAQAAkJ+yOhAwAiAwARAAMJwRfbKwC+AAAAAA==.Aurani:BAAALgAECgEJAQAAAA==.',
Aw='Awyeahdaddy:BAAALgADCgMJAwAAAA==.',
Ay='Ayanna:BAAALgADCgkJFQAAAA==.',
Az='Azale:BAAALgAECgMJAwAAAA==.Azazyl:BAAALgAECgEJAQAAAA==.Azimuth:BAAALgAECgYJBgAAAA==.Azraél:BAAALgADCgEJAQAAAA==.Azulagos:BAAALgADCgYJBgAAAA==.Azzeus:BAABLgAECn8aAAMDAAgJKRngGADjAQADAAgJKRngGADjAQASAAEJmxMfVwAzAAAAAA==.',
Ba='Babyrinsjr:BAABLgAECn8pAAIGAAcJ1BnwOwDYAQAGAAcJ1BnwOwDYAQAAAA==.Baeyn:BAAALgAECgcJDAABLgAFFAMJBQATAA4VAA==.Bagel:BAACLgAFFH8KAAMGAAQJ3hXaLQA6AQAGAAQJ3hXaLQA6AQAUAAMJCAkYAwDMAAAuAAQKfyAABBQACAnIGkEjAHMBABUABQkBFy86AHgBABQABwkJHEEjAHMBAAYABgn9DFVVAGgBAAEuAAUUBgkdAAIAJyQA.Baile:BAAALgAECgEJAQAAAA==.Bakon:BAAALgAECgUJDAAAAA==.Balin:BAAALgADCgYJDgAAAA==.Ballerin:BAAALgADCggJDwABLgAECgYJDQAHAAAAAA==.Bamm:BAAALgAECgQJBAAAAA==.Bamsplat:BAAALgADCgYJDQAAAA==.Barrada:BAABLgAECn8kAAIGAAgJoQtDZABjAQAGAAgJoQtDZABjAQAAAA==.Barricay:BAAALgAECgYJBwAAAA==.Bathroy:BAAALgADCgIJAgAAAA==.',
Be='Bearcane:BAAALgADCgUJBQABLgAFFAUJFQAEANQNAA==.Beardheals:BAAALgAECgQJBAAAAA==.Beardàddy:BAAALgAECgQJBQAAAA==.Bellamira:BAAALgADCgIJAgAAAA==.Benjarrey:BAAALgAECgUJCgAAAA==.Berea:BAABLgAECn8gAAIWAAkJ2QikCQCPAQAWAAkJ2QikCQCPAQAAAA==.',
Bi='Bigmeatyclaw:BAAALgAECgEJBQAAAA==.Billywitchdr:BAAALgADCgEJAQAAAA==.',
Bl='Blankdemonic:BAAALgAECgEJAQAAAA==.Bleedblue:BAABLgAECn8yAAIXAAgJ9xnJEgD4AQAXAAgJ9xnJEgD4AQAAAA==.Blezzy:BAAALgADCgIJAgAAAA==.Bloaf:BAAALgAECgkJBAAAAA==.Blueballmonk:BAAALgAECgYJCgAAAA==.Bluerare:BAABLgAECn83AAIBAAkJSxrvKABgAgABAAkJSxrvKABgAgAAAA==.',
Bo='Bobsgrundle:BAAALgAECgQJBAAAAA==.Bolty:BAAALgADCgUJBQAAAA==.Bonietta:BAAALgADCgIJAgAAAA==.Borahae:BAABLgAFFH8FAAIYAAMJ0wIDCgCuAAAYAAMJ0wIDCgCuAAAAAA==.Bowlinna:BAAALgAECgQJBwAAAA==.',
Br='Brewrosia:BAAALgAECgYJCgAAAA==.Briiki:BAAALgAECgEJAQAAAA==.Brinnohms:BAAALgAECgEJAQAAAA==.Broadsnatl:BAAALgADCgEJAQAAAA==.Bruddah:BAAALgADCgEJAQAAAA==.Brunnhild:BAAALgAECgUJCwAAAA==.Bryxi:BAAALgAECggJEwABLgAECggJIgAZAFkYAA==.Bríelle:BAAALgAECgQJBgAAAA==.Brünhilde:BAACLgAFFH8GAAMSAAIJXwcJNQB8AAASAAIJXwcJNQB8AAAaAAEJngGkNAAkAAAuAAQKfzEAAxIACQlREyYZAOcBABIACQlREyYZAOcBAAMAAgnNCWdjAF8AAAAA.',
Bs='Bstbll:BAACLgAFFH8YAAIPAAcJ/xGNDAD8AQAPAAcJ/xGNDAD8AQAuAAQKfxYAAg8ACQmUHv4JAPQCAA8ACQmUHv4JAPQCAAAA.Bstwaves:BAAALgAECgQJBQAAAA==.',
Bu='Bubbleban:BAAALgADCgUJBQAAAA==.Bubbleheals:BAAALgAECgcJCgABLgAFFAUJEQACAFUNAA==.Bungxi:BAAALgADCgUJBgABLgAECggJIgAZAFkYAA==.Buraddo:BAAALgAECgYJDgABLgAECggJKwAbAHobAA==.Burrata:BAAALgADCgkJCQAAAA==.Buttsnacks:BAABLgAECn8mAAIKAAkJOSHOCgClAgAKAAkJOSHOCgClAgAAAA==.',
Ca='Caciocavallo:BAAALgAECgcJBgAAAA==.Cairebear:BAAALgAECgUJCwAAAA==.Callistrah:BAABLgAECn8xAAMcAAkJXBdxAwDWAQAcAAgJahdxAwDWAQABAAgJXhBjXwCpAQAAAA==.Caltaa:BAABLgAECn9FAAIdAAkJuyXaAABOAwAdAAkJuyXaAABOAwAAAA==.Camael:BAAALgAECgcJDwAAAA==.Canarah:BAAALgADCgUJBQABLgAFFAQJEAAeAM0TAA==.Canverian:BAABLgAECn8pAAIfAAcJRxs8DwDRAQAfAAcJRxs8DwDRAQAAAA==.Carmedic:BAAALgADCgcJDQAAAA==.Carradine:BAAALgADCggJCQAAAA==.',
Ce='Celexa:BAAALgAECgkJDgABLgAECgQJEgAHAAAAAA==.Celtmon:BAAALgADCgIJAwAAAA==.',
Ch='Cha:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.Chapi:BAAALgAECgYJDQAAAA==.Chasseurfool:BAABLgAECn8WAAIGAAYJAQwdjQALAQAGAAYJAQwdjQALAQAAAA==.Chat:BAACLgAFFH8UAAIgAAYJZBzXDACYAQAgAAYJZBzXDACYAQAuAAQKfy8AAiAACQk2G5UOAG8CACAACQk2G5UOAG8CAAAA.Chevalieono:BAAALgADCgIJAgAAAA==.Chewi:BAAALgADCgEJAQAAAA==.Chezaro:BAAALgAECgcJDQAAAA==.Chickenlitle:BAAALgADCgUJBQAAAA==.Chickenwing:BAACLgAFFH8GAAIhAAIJLh7IAgCkAAAhAAIJLh7IAgCkAAAuAAQKfzoAAiEACQnKIJ0AAPgCACEACQnKIJ0AAPgCAAAA.Chilin:BAAALgAECgYJBwAAAA==.Chilindk:BAAALgAECgIJAgABLgAECgYJBwAHAAAAAA==.Chilinevoke:BAAALgAECgMJBAABLgAECgYJBwAHAAAAAA==.Christano:BAABLgAECn8cAAMdAAcJ+RaPGgAqAQAbAAcJrhFnhgBtAQAdAAUJoxuPGgAqAQAAAA==.Christhecold:BAABLgAECn9DAAMiAAkJZB1pDAAKAgAiAAcJqhppDAAKAgAKAAcJ4RcYOQDCAQAAAA==.Chrollo:BAABLgAECn8UAAICAAYJchWQFQBCAQACAAYJchWQFQBCAQAAAA==.Chronoknight:BAAALgADCgkJCQAAAA==.Chronson:BAAALgAECgQJBAAAAA==.Chunt:BAAALgAECgQJCQAAAA==.',
Cl='Clamscasino:BAAALgADCgIJAgABLgAECgcJJQAjAIgOAA==.Clarke:BAAALgADCgMJAwAAAA==.Closets:BAAALgAECgMJAwAAAA==.Cloudcrack:BAACLgAFFH8eAAIgAAgJRRM+BgAQAgAgAAgJRRM+BgAQAgAuAAQKfy8AAiAACQlfHyEMAI4CACAACQlfHyEMAI4CAAAA.Clynt:BAAALgADCgIJAgAAAA==.',
Co='Cocoapuffs:BAAALgADCgIJAgABLgAECgkJOQAJAKQfAA==.Cocotaso:BAAALgAFFAMJBAAAAA==.Codemon:BAABLgAECn8qAAMRAAgJbRPjDAAwAQAQAAgJUQ0QMwBHAQARAAYJSRbjDAAwAQAAAA==.Coldfusion:BAAALgADCgkJCgAAAA==.Condemn:BAAALgADCgEJAgAAAA==.Condiments:BAAALgAECgEJAgAAAA==.Cortar:BAAALgAECgkJEgAAAA==.Cotw:BAAALgAECgIJAwABLgAECgcJDQAHAAAAAA==.',
Cp='Cptcharis:BAAALgADCgYJBgAAAA==.',
Cu='Cubann:BAAALgAECgMJBgAAAA==.',
Cy='Cylrhea:BAABLgAECn8gAAMPAAgJESUIBgBLAwAPAAgJESUIBgBLAwAkAAIJ+AVHdgBDAAAAAA==.Cyntrill:BAAALgAECgUJDAAAAA==.',
Da='Dadderz:BAAALgAECgQJCAAAAA==.Daddydruid:BAAALgAECgQJBgAAAA==.Daemonyx:BAAALgADCgkJEgABLgAECgUJDAAHAAAAAA==.Dahunter:BAABLgAECn8YAAIUAAgJsBpJDwArAgAUAAgJsBpJDwArAgAAAA==.Dajoel:BAAALgAECgYJDQAAAA==.Dakinna:BAAALgADCgMJAwAAAA==.Dakotawolfe:BAAALgADCgUJBQAAAA==.Dalacia:BAACLgAFFH8FAAIeAAIJGhxxSwCmAAAeAAIJGhxxSwCmAAAuAAQKfyAAAh4ACQk3Ex0vAN8BAB4ACQk3Ex0vAN8BAAAA.Dalarik:BAAALgAECgEJAgAAAA==.Dannyrojas:BAAALgAECgEJAgAAAA==.Daphera:BAAALgAECggJCAAAAA==.Darkforceray:BAAALgAECgEJAQAAAA==.Darknature:BAABLgAECn8zAAMPAAkJchLbLQDcAQAPAAkJchLbLQDcAQAkAAcJmBBROQARAQAAAA==.Darkodin:BAABLgAECn8pAAIZAAgJWgvMegBYAQAZAAgJWgvMegBYAQAAAA==.Darkomen:BAAALgADCgcJGQABLgAECggJLgAZAFYQAA==.Darkvlad:BAABLgAECn8uAAIZAAgJVhCYXwCWAQAZAAgJVhCYXwCWAQAAAA==.Datnagadrake:BAACLgAFFH8ZAAMKAAUJRRkAFwBAAQAKAAUJRRkAFwBAAQAlAAIJXxUVCwCWAAAuAAQKf0IAAwoACQn4I8QDAB0DAAoACQn4I8QDAB0DACUAAgldHp0vAKsAAAAA.Davere:BAAALgADCgEJAQAAAA==.Dawinchy:BAACLgAFFH8SAAIPAAUJAw8qHgBIAQAPAAUJAw8qHgBIAQAuAAQKf00ABA8ACQmIFEg0ANcBAA8ACQmIFEg0ANcBACYABwlyC+IZABkBACQAAQmnBZCQACEAAAAA.',
Dc='Dchalla:BAAALgADCgcJDQAAAA==.',
De='Deadlypsycho:BAABLgAECn8VAAIKAAYJlhfRNABhAQAKAAYJlhfRNABhAQAAAA==.Deadmanrise:BAAALgADCgUJBQAAAA==.Deathawakens:BAABLgAFFH8LAAIXAAQJDgx4GwAgAQAXAAQJDgx4GwAgAQAAAA==.Deathchanges:BAAALgAECgIJAQABLgAECgcJEgAHAAAAAA==.Deathlyill:BAAALgAECgcJEgAAAA==.Deathtouch:BAAALgADCgcJDAAAAA==.Decembër:BAABLgAECn8vAAIBAAgJvAh9kAA8AQABAAgJvAh9kAA8AQAAAA==.Decimious:BAAALgAECgQJBwAAAA==.Dekutree:BAABLgAECn8hAAMfAAgJqA4rIAAmAQAfAAgJqA4rIAAmAQAmAAEJsQMeTQAlAAAAAA==.Dellistia:BAAALgAECgYJDgAAAA==.Delvan:BAAALgAECgIJAgAAAA==.Demiglace:BAAALgAECgYJDgAAAA==.Demonkilla:BAAALgAECgYJDwAAAA==.Denadan:BAAALgAECgQJBQABLgAECgkJNAAYANELAA==.Desdamona:BAABLgAECn8iAAIGAAgJUAWufQArAQAGAAgJUAWufQArAQAAAA==.Destrodeath:BAABLgAECn8WAAIZAAkJ3g50SQDTAQAZAAkJ3g50SQDTAQAAAA==.Destrodemon:BAABLgAECn8jAAIEAAgJEhKSYABPAQAEAAgJEhKSYABPAQAAAA==.Destrosham:BAAALgAECgYJBgAAAA==.Deviltango:BAAALgAECgQJBAAAAA==.Devorick:BAABLgAECn84AAMTAAkJPBtHHgBhAgATAAkJPBtHHgBhAgAnAAIJQxCqUQB5AAAAAA==.Deztaknee:BAAALgAECgMJBAAAAA==.',
Di='Diadem:BAAALgAECgMJBAABLgAFFAMJBQATAA4VAA==.Diathian:BAAALgAECgUJBwABLgAFFAYJIQABAOkUAA==.Diaval:BAABLgAECn8dAAIbAAYJbQZ+3gDBAAAbAAYJbQZ+3gDBAAAAAA==.Dih:BAAALgAECgIJAgABLgAECgkJJgAUAMEQAA==.Dihlngthepal:BAAALgAECgEJAQAAAA==.Dirtyzealot:BAAALgADCgkJFwAAAA==.Disenchanted:BAAALgAECgYJBgABLgAECggJHQAQAHMbAA==.Divineknight:BAAALgADCgkJFQAAAA==.Diyiya:BAAALgAECgYJCwAAAA==.',
Dk='Dkchex:BAAALgAECgQJBAAAAA==.',
Dn='Dnkys:BAAALgAECgQJBAAAAA==.',
Do='Dokoth:BAAALgADCgEJAQAAAA==.Doorki:BAAALgAFFAIJBAAAAA==.Doubleott:BAABLgAECn8UAAIGAAcJBxETXQB1AQAGAAcJBxETXQB1AQAAAA==.Doxycycline:BAAALgADCgMJAwABLgAECgYJEwAHAAAAAA==.',
Dr='Drael:BAAALgAECgMJBgAAAA==.Dragonayre:BAAALgAECgUJCQABLgAFFAMJBQATAA4VAA==.Draickin:BAABLgAECn8uAAIjAAgJjBlCFABXAgAjAAgJjBlCFABXAgAAAA==.Drekle:BAABLgAECn8UAAMLAAcJnw9EFQBmAQALAAcJnw9EFQBmAQAQAAEJeQOwkwAXAAAAAA==.Drelian:BAAALgAECgUJCgAAAA==.Drenzel:BAAALgADCgYJCQAAAA==.Drevy:BAABLgAECn8WAAQXAAcJHhbEKAA1AQAXAAcJHhbEKAA1AQAoAAMJOgiTDABdAAAWAAEJAADLKgAAAAAAAA==.Drewsguy:BAAALgAECgQJCwAAAA==.Drexchan:BAAALgAECgYJEAAAAA==.Drexen:BAAALgADCgQJBQAAAA==.Drexy:BAAALgAECgEJAQAAAA==.Drhoger:BAAALgAECgUJCwAAAA==.Dropdahammer:BAAALgADCgUJBQAAAA==.Drumma:BAAALgAECgYJDgAAAA==.Drumroleplz:BAABLgAECn8dAAMQAAgJcxsbJQCaAQARAAYJyh2ZEwCrAQAQAAcJ7BUbJQCaAQAAAA==.',
Ds='Dsanatrestk:BAABLgAECn8oAAMZAAkJ3iT0EQDMAgAZAAkJ3iT0EQDMAgAJAAcJ1RpaEAAFAgAAAA==.',
Du='Dumbguy:BAAALgAECgYJCgABLgAECgkJJwATAJgiAA==.Dumbman:BAAALgAECgcJCgABLgAECgkJJwATAJgiAA==.',
Dw='Dw:BAAALgADCgYJCgAAAA==.',
['Dà']='Dàddybear:BAABLgAECn8ZAAIGAAkJRBBeYgBoAQAGAAkJRBBeYgBoAQAAAA==.',
Ea='Earthsangel:BAAALgAECggJDgAAAA==.',
Ec='Eclair:BAABLgAFFH8QAAIdAAQJ2BLSBgD5AAAdAAQJ2BLSBgD5AAAAAA==.',
Ed='Edralyia:BAAALgAECgYJDgAAAA==.',
Ei='Eilaurosa:BAABLgAECn9BAAIWAAkJ/BjdAwBUAgAWAAkJ/BjdAwBUAgAAAA==.Einnarr:BAAALgADCgYJBgAAAA==.',
El='Eldrinne:BAABLgAECn8bAAIhAAgJLQWjBwD3AAAhAAgJLQWjBwD3AAAAAA==.Elftuah:BAAALgADCggJCAAAAA==.Elfö:BAABLgAECn8VAAIGAAkJThVsPQDTAQAGAAkJThVsPQDTAQAAAA==.Elizawrath:BAABLgAECn85AAMdAAkJwCJ8AgDzAgAdAAkJwCJ8AgDzAgAjAAUJlBHkWgARAQAAAA==.Elkuco:BAAALgAECgIJAgAAAA==.Elthiss:BAABLgAECn88AAIfAAgJShxbCgAfAgAfAAgJShxbCgAfAgAAAA==.Elusuma:BAAALgAECgkJBwAAAA==.',
Em='Emariel:BAAALgAFFAEJAQAAAA==.',
En='Enchäntress:BAACLgAFFH8HAAITAAMJdAJIfQCqAAATAAMJdAJIfQCqAAAuAAQKfx4AAxMACQnmDUBTAJYBABMACQnmDUBTAJYBABgAAQkAAIM3ACMAAAAA.Enfer:BAAALgADCgYJCAABLgAFFAYJFAAgAGQcAA==.Enogg:BAAALgAECgYJCQAAAA==.Envi:BAABLgAECn9AAAMBAAkJQBtrJQBwAgABAAkJQBtrJQBwAgAcAAEJWRWfEQBAAAAAAA==.',
Ep='Ephraìm:BAAALgAECgcJBwAAAA==.',
Er='Erianthe:BAABLgAECn80AAIZAAkJswoHXwCYAQAZAAkJswoHXwCYAQAAAA==.Eroar:BAAALgADCgYJBgAAAA==.Erophien:BAAALgADCgkJLAABLgAECgcJHAAUABsIAA==.Erovael:BAAALgADCgQJBAABLgAECgcJHAAUABsIAA==.Erovynael:BAABLgAECn8cAAMUAAcJGwgfLAAyAQAUAAcJGwgfLAAyAQAGAAQJeANewwCbAAAAAA==.',
Ev='Eversong:BAAALgAECgYJEQAAAA==.Evhi:BAAALgAECgYJCQAAAA==.',
Ex='Exmar:BAAALgAECgMJAwAAAA==.',
Fa='Faewhisker:BAAALgAECgQJBAAAAA==.Faey:BAAALgADCgQJBAAAAA==.Falnor:BAAALgADCgkJDAABLgAECgkJKwADAHsaAA==.Famine:BAABLgAECn8kAAMZAAkJaBzyMQBwAgAZAAkJaBzyMQBwAgApAAEJAAA1OwAAAAAAAA==.Fancyfeet:BAAALgAFFAEJAQABLgAFFAYJGAAXAGsXAA==.Fangmonarch:BAAALgADCgEJAQAAAA==.',
Fc='Fckmalfurion:BAAALgADCgkJEgABLgAECgkJJgAUAMEQAA==.',
Fe='Fearios:BAABLgAECn85AAIJAAkJpB+eBQC8AgAJAAkJpB+eBQC8AgAAAA==.Febronia:BAAALgAECgUJBQAAAA==.Felbeast:BAAALgAECgYJBQAAAA==.Felbound:BAAALgAECgEJAQAAAA==.Felltheburn:BAAALgADCgEJAQAAAA==.',
Fi='Figmênt:BAAALgAECgUJDgABLgAECgcJJQAjAIgOAA==.Finatic:BAAALgAECgMJAwAAAA==.Finneous:BAABLgAECn8ZAAQFAAcJXhqCGgDEAQAFAAcJXhqCGgDEAQAIAAEJQh0rdABPAAAOAAEJlgP8sQAaAAAAAA==.Fireproof:BAABLgAECn8bAAMdAAcJjiKPCABPAgAdAAcJOiCPCABPAgAbAAcJyBv+OQA7AgAAAA==.Fistedwaffle:BAAALgAECgEJAQABLgAFFAMJBAAHAAAAAA==.Fistopher:BAAALgAECgEJAQAAAA==.',
Fj='Fjorskin:BAAALgAECgQJBAAAAA==.',
Fl='Flairdragin:BAAALgAECgYJDQAAAA==.Flare:BAAALgAECggJEgAAAA==.',
Fo='Forix:BAAALgADCggJDAAAAA==.',
Fr='Fries:BAAALgADCggJCAAAAA==.Frosttbyte:BAABLgAECn8dAAIBAAkJcByZKABiAgABAAkJcByZKABiAgAAAA==.Frostytute:BAAALgADCgcJEQAAAA==.Frozenwitch:BAAALgADCgUJBQAAAA==.',
Fu='Fullmetalass:BAAALgADCggJCAABLgAECgIJAgAHAAAAAA==.Funnelcake:BAAALgADCgcJBgAAAA==.Funsies:BAAALgADCgEJAQAAAA==.',
Fy='Fyrrstorm:BAAALgAECgMJAwAAAA==.',
['Fë']='Fëiróx:BAAALgADCgYJBgAAAA==.',
Ga='Gallum:BAAALgADCgEJAQAAAA==.Gamuza:BAAALgAECgQJBAAAAA==.',
Ge='Getzi:BAABLgAECn8cAAIbAAkJ4CH8FQDlAgAbAAkJ4CH8FQDlAgAAAA==.',
Gh='Ghavinflip:BAABLgAECn8XAAIFAAgJARIJIgCJAQAFAAgJARIJIgCJAQAAAA==.',
Gi='Gil:BAABLgAECn87AAIEAAkJCyOsBgAPAwAEAAkJCyOsBgAPAwAAAA==.Gimlita:BAAALgAECgIJAgABLgAECggJIgAZAFkYAA==.Gindraxx:BAAALgADCgEJAQAAAA==.',
Gl='Glocket:BAAALgADCgEJAQAAAA==.',
Go='Goatspace:BAAALgADCgcJDgABLgAECgkJNAAYANELAA==.Goettel:BAAALgAECgUJBQAAAA==.Gogmazios:BAAALgADCgEJAQAAAA==.Gogofisco:BAAALgAECgEJAgAAAA==.Gongagà:BAAALgAECgYJDAAAAA==.Goodnoodle:BAAALgADCgEJAQAAAA==.Gothbaddie:BAAALgAECgcJBwAAAA==.Goyum:BAAALgAECgQJBAAAAA==.',
Gr='Grankino:BAABLgAECn8iAAImAAcJKRhCDgCuAQAmAAcJKRhCDgCuAQAAAA==.Grapenuts:BAAALgADCgEJAQABLgAECgkJOQAJAKQfAA==.Grayves:BAAALgAECgUJBAAAAA==.Greenthumbs:BAABLgAECn8ZAAIkAAgJNAjoOgAKAQAkAAgJNAjoOgAKAQAAAA==.Greyhulk:BAABLgAECn8YAAMZAAcJKQ6VlAApAQAZAAcJKQ6VlAApAQAJAAUJhwZPPwB4AAAAAA==.Grinlock:BAAALgADCgEJAQAAAA==.',
Gu='Guldanshower:BAAALgADCgIJAgAAAA==.Gurni:BAAALgADCgYJCAAAAA==.Guthan:BAAALgAECgEJAQAAAA==.Guthild:BAAALgAECgIJAgAAAA==.',
Gw='Gwaelphypha:BAABLgAECn8iAAMZAAgJWRj9RAAmAgAZAAgJnBf9RAAmAgAJAAcJlBERIQAwAQAAAA==.',
Ha='Hakarii:BAAALgADCgYJDAAAAA==.Halder:BAAALgAECgEJAQAAAA==.Halliax:BAAALgADCgYJBgABLgAFFAMJBQATAA4VAA==.Hamburglar:BAAALgADCgYJCAAAAA==.Hapkido:BAABLgAECn9HAAQOAAkJtyTNAQCqAwAOAAkJtyTNAQCqAwAFAAEJcgTfoAAkAAAIAAEJxwmzlAAiAAAAAA==.Hardsus:BAAALgAECgQJAwAAAA==.Hauwitzer:BAAALgAECgQJBQAAAA==.Hawfmave:BAAALgAECgcJEQAAAA==.',
He='Heals:BAAALgAECgMJAwAAAA==.Healsmcnasty:BAAALgADCgEJAQAAAA==.Healthpotion:BAAALgAECgMJAwAAAA==.Heartbroken:BAAALgAECgkJBwAAAA==.Hecate:BAABLgAECn8bAAIbAAgJKAUutwD4AAAbAAgJKAUutwD4AAAAAA==.Heidnik:BAAALgAECgQJCAAAAA==.Helvetica:BAAALgADCggJDwAAAA==.Heretic:BAAALgAECgUJDAAAAA==.Hessdemon:BAAALgAECgYJDgAAAA==.',
Hi='Hillboy:BAAALgAFFAIJBAAAAA==.Hippiehulk:BAAALgAECgEJAQAAAA==.',
Ho='Holydes:BAAALgAECgQJCwABLgAECggJIgAGAFAFAA==.Holyfrejoles:BAAALgAECgkJAwAAAA==.Holyshrimp:BAABLgAECn85AAIDAAkJIR6oBwC9AgADAAkJIR6oBwC9AgAAAA==.Honeydew:BAAALgAECgkJAQABLgAECgkJAgAHAAAAAA==.Hordor:BAAALgAECgEJAQAAAA==.Hotndot:BAAALgADCgcJCgAAAA==.',
Hu='Humboldt:BAAALgAECgEJAQABLgAECgcJBgAHAAAAAA==.Hummakavulä:BAAALgAECgUJDAAAAA==.Hunkahunka:BAAALgAECgMJBAAAAA==.Huunaron:BAABLgAECn8jAAMjAAgJNhmHJADNAQAjAAgJNhmHJADNAQAbAAQJUwed9gCjAAABLgAFFAQJBgASAJISAA==.',
Id='Idylwilde:BAABLgAECn8YAAMkAAYJPwYyUQCtAAAkAAYJPwYyUQCtAAAmAAEJOgdMUAAgAAAAAA==.',
Ie='Ienzo:BAAALgADCgUJBQAAAA==.',
If='Ifunny:BAAALgAECgcJCgAAAA==.',
Ih='Iheartoreos:BAABLgAECn8zAAMJAAkJMhRpFACzAQAJAAkJIBRpFACzAQApAAQJLwnwDgCzAAAAAA==.',
Il='Illiblades:BAAALgAECgQJBAABLgAFFAYJGAANAPgiAA==.Ilovefuta:BAABLgAFFH8IAAIIAAMJ+BLmLwDSAAAIAAMJ+BLmLwDSAAAAAA==.',
In='Ineedoreos:BAAALgAECgYJCQAAAA==.Inferna:BAAALgAECgQJBAAAAA==.Infidelis:BAAALgAECgEJAQAAAA==.Ink:BAABLgAFFH8GAAIZAAMJfxbpOwClAAAZAAMJfxbpOwClAAAAAA==.Inmortuae:BAAALgAECgMJAwAAAA==.Instakill:BAAALgADCgYJCQAAAA==.Insulin:BAAALgADCgkJEgAAAA==.Invictae:BAABLgAECn8aAAQSAAgJXg0ILABTAQASAAYJYxAILABTAQADAAcJ3wdXPwDuAAAaAAQJwAwNSgCiAAAAAA==.',
Io='Iobo:BAACLgAFFH8UAAIEAAgJ1BhDEwDXAQAEAAgJ1BhDEwDXAQAuAAQKfxgAAgQACQl4Ig8HAFYDAAQACQl4Ig8HAFYDAAAA.',
Ir='Iradori:BAABLgAFFH8hAAIBAAYJ6RRKLACLAQABAAYJ6RRKLACLAQAAAA==.Irønbane:BAAALgAECgEJAQAAAA==.',
Is='Iskandar:BAAALgAECgYJCgAAAA==.Isparian:BAABLgAECn8wAAQbAAgJ1hqlRgDaAQAbAAgJdBmlRgDaAQAdAAUJLA5mJwDAAAAjAAEJiwmUigAqAAAAAA==.Issior:BAAALgAECgMJAwAAAA==.',
Ja='Jaegar:BAAALgADCgIJAgAAAA==.Jamal:BAAALgADCgkJGwAAAA==.Jarco:BAEBLgAFFH8PAAQGAAUJmR/FHQBjAQAGAAUJmR/FHQBjAQAUAAEJigTaLgBCAAAVAAEJAACOMgAAAAAAAA==.Jasmyn:BAAALgADCgEJAQAAAA==.Jasseca:BAAALgADCggJCAABLgAECggJIgAZAFkYAA==.Java:BAABLgAECn8aAAITAAcJURFwcABPAQATAAcJURFwcABPAQAAAA==.',
Je='Jeandarc:BAAALgADCgkJCQAAAA==.',
Jo='Joedakilla:BAAALgAECgEJAQAAAA==.Jonorin:BAAALgADCgEJAQAAAA==.',
Js='Jshaman:BAABLgAECn8XAAMeAAYJ6wdkhACyAAAeAAUJ9QdkhACyAAAgAAYJMgMzZwCSAAAAAA==.',
Ju='Judoken:BAABLgAECn8VAAMXAAYJIAeBNgDbAAAXAAYJHAeBNgDbAAAWAAUJUwLnFACsAAAAAA==.Jupiterr:BAABLgAFFH8HAAMVAAMJvRk4EwAKAQAVAAMJvRk4EwAKAQAGAAEJkRMrhABLAAABLgAFFAUJDwAEAMUYAA==.Justapotato:BAAALgADCgIJAgAAAA==.',
Ka='Kaadra:BAAALgAECgEJAQAAAA==.Kaeldach:BAAALgAECgYJCwAAAA==.Kaelgen:BAAALgAECggJCwAAAA==.Kaelkin:BAABLgAECn8YAAMSAAgJhhgTEwAqAgASAAgJhhgTEwAqAgADAAEJDhuZaQBOAAABLgAECgkJKAACAEAWAA==.Kaelthlar:BAAALgAECgIJAwAAAA==.Kaelun:BAAALgAECgQJBwABLgAECgkJKAACAEAWAA==.Kaelundrus:BAABLgAECn8oAAMCAAkJQBatCwDcAQACAAgJTBitCwDcAQAeAAYJkBmuQACOAQAAAA==.Kainis:BAABLgAECn8aAAIVAAcJzAavFwDgAAAVAAcJzAavFwDgAAAAAA==.Kairia:BAAALgADCgEJAQAAAA==.Kalvinakri:BAAALgADCgkJDgAAAA==.Karasana:BAAALgAECgQJBAAAAA==.Karmus:BAAALgAECggJEwAAAA==.Kastaspella:BAABLgAECn8bAAIBAAcJnhDihwBMAQABAAcJnhDihwBMAQAAAA==.Kau:BAABLgAECn8VAAIWAAYJFQSmFQC7AAAWAAYJFQSmFQC7AAAAAA==.Kawant:BAAALgAECgIJAwAAAA==.Kaylnee:BAABLgAECn8mAAIeAAcJXxK+QQCKAQAeAAcJXxK+QQCKAQAAAA==.',
Ke='Keadin:BAAALgAECgYJDwAAAA==.Kearra:BAAALgADCgkJCQAAAA==.Kehayne:BAAALgADCgQJBAAAAA==.Keilas:BAABLgAECn8bAAImAAgJHx7UBQByAgAmAAgJHx7UBQByAgAAAA==.Kerro:BAAALgAECgIJAwAAAA==.Kerron:BAAALgADCgMJAwAAAA==.Keyes:BAACLgAFFH8lAAIIAAgJ2BiXAQD8AQAIAAgJ2BiXAQD8AQAuAAQKfycAAggACQlsIXgHAK0CAAgACQlsIXgHAK0CAAAA.Keylala:BAABLgAECn8oAAMnAAcJzBXwCgB1AQAnAAcJzBXwCgB1AQATAAIJTwR3DAFHAAAAAA==.',
Ki='Kiafera:BAAALgADCgMJAwAAAA==.Kibo:BAAALgAECgMJAwAAAA==.Kickenmage:BAAALgAECggJBwAAAA==.Kickentail:BAAALgAECgYJDwABLgAECggJBwAHAAAAAA==.Kidx:BAAALgAECgMJAwAAAA==.Kimjunggoon:BAAALgAECgEJAQAAAA==.Kimunkamuy:BAAALgAECgYJBgAAAA==.Kiraw:BAAALgAECgIJBAAAAA==.Kirisham:BAAALgAECgQJBAAAAA==.Kirlia:BAAALgAECgMJBgAAAA==.Kishenia:BAAALgAECgIJAgAAAA==.',
Kl='Kleanx:BAAALgADCgYJDgAAAA==.Klymax:BAAALgADCgUJBQAAAA==.',
Ko='Kongor:BAABLgAECn8oAAICAAgJ3ByVCAAgAgACAAgJ3ByVCAAgAgAAAA==.Korathazan:BAAALgADCgEJAQAAAA==.Korithelse:BAAALgAECgEJAQAAAA==.Korthea:BAAALgAECgIJAgAAAA==.',
Kr='Krispitreat:BAAALgAECgYJCwAAAA==.Kritnespears:BAAALgAECgcJEgABLgAECggJDAAHAAAAAA==.Krobelus:BAABLgAECn89AAMbAAkJ5wykbQB5AQAbAAkJ5wykbQB5AQAjAAYJVQXpZADoAAAAAA==.Kryptik:BAAALgADCgEJAQAAAA==.',
Kv='Kvedaheillr:BAAALgAECgMJAwAAAA==.Kvedaroðull:BAAALgADCgYJBwAAAA==.Kvedathulr:BAAALgADCgYJBgAAAA==.',
Ky='Kyehole:BAAALgAECgMJAwAAAA==.Kylearean:BAAALgADCgYJBgAAAA==.Kyluna:BAAALgAECgEJAQAAAA==.',
['Kè']='Kères:BAAALgAECgYJDQAAAA==.Kèrónos:BAAALgAECgQJCwAAAA==.',
['Kì']='Kìllstheweak:BAABLgAECn8xAAMpAAkJGBDSDQBoAQApAAkJVg/SDQBoAQAJAAYJ3QwPJwAGAQAAAA==.',
La='Lauralai:BAAALgAECgMJAwAAAA==.Lavendra:BAAALgADCgcJDwAAAA==.Lawkz:BAAALgAECgcJCAAAAA==.Layliah:BAACLgAFFH8dAAIkAAYJrSNiBwDjAQAkAAYJrSNiBwDjAQAuAAQKf0gAAiQACQlJJVQBAGgDACQACQlJJVQBAGgDAAAA.',
Le='Leafless:BAAALgAECgEJAQAAAA==.Leaftemplar:BAAALgADCgYJBgAAAA==.Leedragoon:BAAALgADCgMJAwAAAA==.Legaia:BAAALgADCgYJCQAAAA==.Legendknewl:BAAALgAECgQJBAAAAA==.Leilara:BAAALgADCgcJCwAAAA==.Lemmesapthat:BAAALgADCgEJAQAAAA==.Leviathonian:BAAALgAECgEJAgAAAA==.',
Li='Lightseeker:BAAALgAECgEJAQAAAA==.Lillinna:BAAALgADCgQJBAAAAA==.Lilthina:BAAALgADCgcJBwABLgAECgcJJgAeAF8SAA==.Lisithen:BAAALgADCgEJAQAAAA==.Littlespoon:BAAALgAECgQJCAAAAA==.',
Lo='Loafai:BAABLgAECn80AAQYAAkJ0Qt7CwCDAQAYAAgJpwx7CwCDAQAnAAYJ/gfUGwCzAAATAAcJAgQb1QCwAAAAAA==.Lockrocks:BAABLgAECn8jAAITAAgJgRz4LQAUAgATAAgJgRz4LQAUAgAAAA==.Lockycharmz:BAAALgAECgMJAwABLgAECgkJOQAJAKQfAA==.Lorcán:BAAALgAECgYJDgAAAA==.Lormazlezrax:BAACLgAFFH8QAAIeAAQJzRMHLgAHAQAeAAQJzRMHLgAHAQAuAAQKfyQAAh4ABwltIBUZAE0CAB4ABwltIBUZAE0CAAAA.Lowlife:BAAALgAECggJDAAAAA==.',
Lu='Luis:BAAALgAECgQJBAAAAA==.Lumaron:BAAALgADCgEJAgAAAA==.Lunamizka:BAAALgADCgIJAgAAAA==.Lunella:BAAALgAFFAEJAQAAAA==.Lunethira:BAAALgAECgUJDwABLgAFFAEJAQAHAAAAAA==.Lupe:BAAALgAECgcJBwAAAA==.Lustdeeznuts:BAABLgAECn8XAAIgAAYJjRtiMQBeAQAgAAYJjRtiMQBeAQAAAA==.',
Ly='Lylat:BAAALgAECgIJAgAAAA==.',
['Ló']='Lórdelrond:BAAALgAECgIJAgAAAA==.',
['Lú']='Lúpo:BAAALgAECgYJDQAAAA==.',
Ma='Machezemo:BAACLgAFFH8MAAIBAAMJhhZXawDrAAABAAMJhhZXawDrAAAuAAQKfyAAAgEACAlhH5dMAN4BAAEACAlhH5dMAN4BAAAA.Madhatter:BAAALgAECgUJBwAAAA==.Mahalka:BAAALgAECgEJAQAAAA==.Maki:BAABLgAECn8kAAIaAAgJeiIXBgADAwAaAAgJeiIXBgADAwAAAA==.Malegar:BAAALgADCgkJIQAAAA==.Malendor:BAABLgAECn8zAAIFAAkJmSbRAAB1AwAFAAkJmSbRAAB1AwAAAA==.Mallaki:BAAALgADCgMJAwAAAA==.Mammajamma:BAAALgAECgEJAwABLgAECgQJCAAHAAAAAA==.Manbearcat:BAAALgAECgYJDQAAAA==.Marcydaghoul:BAAALgADCgUJBQAAAA==.Marivoker:BAAALgAECgQJCgABLgAECgYJDAAHAAAAAA==.Marsvolta:BAAALgADCgYJBgAAAA==.Maruxus:BAACLgAFFH8FAAIWAAMJDQsDBwDcAAAWAAMJDQsDBwDcAAAuAAQKfzoAAxYACQldGrwCAIsCABYACQldGrwCAIsCACgABgl+D0wGAGEBAAAA.Marvilla:BAAALgAECgkJEgAAAA==.Marwen:BAAALgAECgQJCwAAAA==.Mathbrew:BAEBLgAECn8mAAIIAAgJ6SG2CQCHAgAIAAgJ6SG2CQCHAgABLgAFFAMJBgAZALgWAA==.Mathbruh:BAEALgAECgQJBAABLgAFFAMJBgAZALgWAA==.Maulsin:BAAALgAECgcJDgAAAA==.',
Mc='Mcchicken:BAAALgADCgIJAgAAAA==.Mclardragos:BAABLgAECn8gAAILAAkJvhx2BQCsAgALAAkJvhx2BQCsAgAAAA==.',
Me='Meatshield:BAAALgAECgQJBAABLgAECgQJBwAHAAAAAA==.Mecharoni:BAAALgAECggJCwABLgAECgkJQQAQAPsjAA==.Medreaux:BAAALgAECgkJAgAAAA==.Mehv:BAEALgAECgkJCwAAAQ==.Melindria:BAABLgAECn8iAAMkAAgJjQuBPwA0AQAkAAYJHw+BPwA0AQAfAAgJawTuOACaAAABLgAECgkJHwAeAJIYAA==.Mendicine:BAABLgAECn8jAAIPAAgJLBykFACRAgAPAAgJLBykFACRAgAAAA==.Menmoe:BAAALgAECgEJAQAAAA==.',
Mf='Mfdoom:BAAALgAECgMJAwAAAA==.',
Mi='Miacyn:BAAALgAECgcJDQAAAA==.Miladybast:BAABLgAECn8nAAIBAAgJWwQlvADyAAABAAgJWwQlvADyAAAAAA==.Miniwheet:BAAALgAECgYJCgABLgAECgkJOQAJAKQfAA==.Mirra:BAABLgAECn8fAAIGAAgJpAsoYQBrAQAGAAgJpAsoYQBrAQAAAA==.Misha:BAAALgADCgUJBQAAAA==.Missdorei:BAAALgAECgUJCAAAAA==.',
Mo='Mogged:BAABLgAECn8vAAIBAAgJlSEUHACdAgABAAgJlSEUHACdAgAAAA==.Mojocity:BAAALgADCgYJCwAAAA==.Molai:BAAALgAECgcJBAAAAA==.Monkdangit:BAAALgAECgYJCQAAAA==.Mordraidas:BAAALgADCgkJCQAAAA==.Morionso:BAABLgAECn8tAAIdAAgJTxwRCQAnAgAdAAgJTxwRCQAnAgAAAA==.Morphyrinsjr:BAAALgADCgcJEgABLgAECgcJKQAGANQZAA==.Mortarion:BAABLgAECn86AAIZAAkJNCGIDQDvAgAZAAkJNCGIDQDvAgAAAA==.Moxxulae:BAAALgADCgkJCAAAAA==.Moõn:BAABLgAECn8pAAIQAAkJTRBCIgCtAQAQAAkJTRBCIgCtAQAAAA==.',
Mu='Murcié:BAABLgAECn8pAAMEAAgJLxakOAASAgAEAAgJLxakOAASAgANAAYJHwkQOgAZAQAAAA==.Murdiûs:BAABLgAECn8kAAIOAAkJ7RtoEgBqAgAOAAkJ7RtoEgBqAgAAAA==.',
My='Myaliki:BAAALgADCgcJBwABLgAECgUJCQAHAAAAAA==.Myregards:BAAALgADCgYJBwAAAA==.Myspaceshria:BAAALgAECgUJDgABLgAECggJIgAZAFkYAA==.Mythbruh:BAECLgAFFH8GAAIZAAMJuBbZegDoAAAZAAMJuBbZegDoAAAuAAQKfx8AAxkACAnAIUElAFsCABkACAn6IEElAFsCAAkABwmVIZcMACgCAAAA.Mythis:BAAALgAECgMJBAAAAA==.',
['Mó']='Mósh:BAAALgAECgYJBgAAAA==.',
Na='Nahane:BAAALgAECgQJBAAAAA==.Nahlur:BAAALgAECgMJAwAAAA==.Naoko:BAAALgAECgEJAgAAAA==.Natani:BAAALgADCgkJEQAAAA==.Nayrlock:BAACLgAFFH8FAAITAAMJDhUbZgDeAAATAAMJDhUbZgDeAAAuAAQKfyoABBMACQkTIEkaALcCABMACQkTIEkaALcCABgABQm1F18RABcBACcABAm4EKRAALIAAAAA.Nayuta:BAAALgADCgYJBQAAAA==.Nazal:BAAALgADCgEJAQABLgADCgEJAQAHAAAAAA==.',
Nc='Nc:BAAALgAECgEJAQAAAA==.Nctee:BAABLgAECn8YAAIBAAcJ/BSBgQBaAQABAAcJ/BSBgQBaAQAAAA==.',
Ne='Necrodwarf:BAAALgADCgEJAQAAAA==.Necropally:BAAALgAECgQJBwAAAA==.Necrotizor:BAABLgAECn8jAAMTAAgJzB0oJwAyAgATAAgJzB0oJwAyAgAnAAEJNBWuNgA4AAAAAA==.Neonsalmandr:BAAALgAECgEJAQAAAA==.Nerfhammer:BAAALgADCgIJAgAAAA==.Nerrol:BAAALgADCgkJCQAAAA==.',
Ni='Nialliv:BAAALgADCgcJCQAAAA==.Nidvin:BAABLgAECn8bAAIeAAYJURxvMADYAQAeAAYJURxvMADYAQAAAA==.Nightsmoke:BAAALgAECgQJBQAAAA==.Nixa:BAAALgADCgcJCgAAAA==.',
Nk='Nkb:BAAALgAECgYJDAAAAA==.',
Nn='Nnoitra:BAAALgADCgcJBwAAAA==.',
No='Noceman:BAAALgADCgEJAQAAAA==.Nock:BAAALgAECgkJEAAAAA==.Nogg:BAAALgAECgEJAQAAAA==.Nolanel:BAAALgAECggJCwAAAA==.Noll:BAAALgADCgUJBQAAAA==.Nonattarius:BAAALgAECgYJCwAAAA==.Norezfou:BAABLgAECn8+AAMaAAkJKyBZCwCaAgAaAAkJKyBZCwCaAgADAAYJgRsLHgC2AQAAAA==.Nornir:BAAALgAECgIJAgAAAA==.Norran:BAABLgAECn8gAAMDAAkJGRt9DQBhAgADAAkJGRt9DQBhAgASAAYJvBmQIgCWAQAAAA==.Norvera:BAAALgAECgIJAgAAAA==.Notalice:BAAALgAECgYJBwAAAA==.Notmywife:BAAALgAECgYJDQAAAA==.Novakri:BAAALgADCgUJCAABLgADCgYJDAAHAAAAAA==.',
Nu='Nuker:BAABLgAECn8dAAIBAAgJkwdRlwAvAQABAAgJkwdRlwAvAQAAAA==.Nurobi:BAABLgAECn8fAAIkAAgJkhRDJgCBAQAkAAgJkhRDJgCBAQAAAA==.Nuundix:BAABLgAECn8WAAIgAAgJhwftQwAIAQAgAAgJhwftQwAIAQAAAA==.',
Ny='Nyri:BAAALgADCgEJAQAAAA==.Nysel:BAAALgAECgkJAQAAAA==.Nysera:BAAALgADCggJCAAAAA==.Nyxy:BAAALgAECgUJDAAAAA==.',
Oc='Ocey:BAAALgAECgIJAwABLgAECgkJGgAPAG4YAA==.',
Od='Odyn:BAABLgAECn8mAAIbAAgJ/RxQJABbAgAbAAgJ/RxQJABbAgAAAA==.',
Oo='Ooyu:BAAALgAECgUJCwAAAA==.',
Or='Orangepeel:BAAALgADCgUJBQAAAA==.Oridk:BAABLgAECn8UAAIZAAgJTRUfjABoAQAZAAgJTRUfjABoAQABLgAFFAUJFwAUADsfAA==.Orimage:BAAALgADCgkJDAABLgAFFAUJFwAUADsfAA==.Oripal:BAAALgAECgUJBQABLgAFFAUJFwAUADsfAA==.Orisham:BAAALgADCgkJCQABLgAFFAUJFwAUADsfAA==.Oríon:BAACLgAFFH8XAAIUAAUJOx+9BwB8AQAUAAUJOx+9BwB8AQAuAAQKfyYAAxQACQkuI7sFALECABQACQkuI7sFALECABUABQlqFgtTAAABAAAA.',
Ou='Outofmyele:BAAALgADCgQJBAAAAA==.',
Ow='Owoker:BAABLgAECn8WAAIRAAgJJRotBgDdAQARAAgJJRotBgDdAQAAAA==.',
Pa='Pablo:BAABLgAECn8VAAImAAcJ3xl8CwAHAgAmAAcJ3xl8CwAHAgAAAA==.Pancaked:BAAALgAECgEJAQABLgAFFAYJHQACACckAA==.Pancakedup:BAAALgAECgcJDAABLgAFFAYJHQACACckAA==.Pandozer:BAAALgAECggJEgAAAA==.Pankratos:BAABLgAECn8WAAMIAAkJliOyFABoAgAIAAkJliOyFABoAgAFAAMJLyB/OwD6AAAAAA==.Papaspud:BAABLgAECn8zAAIaAAkJ3A9HIQCjAQAaAAkJ3A9HIQCjAQAAAA==.Paradias:BAACLgAFFH8YAAIXAAYJaxeeCQC0AQAXAAYJaxeeCQC0AQAuAAQKfzAAAxcACAm2IPYMAMoCABcACAmaIPYMAMoCABYABgmxFzEMAGIBAAAA.Pastor:BAAALgAECgYJEwAAAA==.Patpat:BAAALgADCgcJBgAAAA==.Paxxfist:BAABLgAECn8iAAIOAAgJ+RJpKQCyAQAOAAgJ+RJpKQCyAQAAAA==.',
Pe='Peachdevil:BAAALgAECgEJAQAAAA==.Penryn:BAAALgAECgEJAQAAAA==.Pentive:BAACLgAFFH8JAAImAAMJeiBQBwAZAQAmAAMJeiBQBwAZAQAuAAQKfxsAAiYACAljHDkFAL0CACYACAljHDkFAL0CAAAA.Peppersgotem:BAAALgAECgEJAQAAAA==.Peppersham:BAABLgAECn8pAAMgAAcJWRvqHQDZAQAgAAcJWRvqHQDZAQAeAAIJVxkVgQCPAAAAAA==.Peppersmonk:BAAALgAECgEJAQAAAA==.Pepromene:BAAALgADCgUJBQAAAA==.Perff:BAAALgADCgYJBQAAAA==.Perhaps:BAACLgAFFH8KAAIIAAMJHiPpGQA3AQAIAAMJHiPpGQA3AQAuAAQKfxwAAggACAkbIokHAA0DAAgACAkbIokHAA0DAAAA.Persephone:BAAALgADCgYJBgAAAA==.Petesdragin:BAABLgAECn8mAAILAAcJ9xXSDgDNAQALAAcJ9xXSDgDNAQAAAA==.',
Pf='Pfftpfft:BAABLgAECn8bAAIGAAgJVh7aHABjAgAGAAgJVh7aHABjAgAAAA==.',
Ph='Phatdanny:BAABLgAECn8VAAIbAAgJcBjkUQC7AQAbAAgJcBjkUQC7AQAAAA==.Phatdumpy:BAABLgAECn8mAAQUAAkJwRDMFwDUAQAUAAkJbA3MFwDUAQAGAAcJcRO0OgDEAQAVAAQJ7wr/XADOAAAAAA==.Phattphatt:BAABLgAECn8bAAImAAcJEBpkDgCsAQAmAAcJEBpkDgCsAQAAAA==.Phonycheese:BAABLgAECn8UAAMbAAgJkQ5NpgA0AQAbAAYJORNNpgA0AQAjAAMJuRf8ZwB3AAAAAA==.Phur:BAABLgAFFH8NAAIiAAMJeB+OFQAKAQAiAAMJeB+OFQAKAQAAAA==.',
Pi='Pinbal:BAAALgAECgQJBAAAAA==.Pixen:BAABLgAECn86AAITAAkJkRkPHABuAgATAAkJkRkPHABuAgAAAA==.',
Pl='Plagueiss:BAABLgAECn8cAAIZAAgJjhrPPABEAgAZAAgJjhrPPABEAgAAAA==.',
Po='Pocalypse:BAAALgAECgYJBQAAAA==.Pocketsand:BAAALgADCgkJDwAAAA==.Poisònivy:BAAALgAECgUJBQAAAA==.Ponkeylips:BAACLgAFFH8NAAIKAAUJBh46EQBdAQAKAAUJBh46EQBdAQAuAAQKfxsAAwoACAnaH/cMAIkCAAoACAnaH/cMAIkCACIAAQnNBsNDADEAAAAA.Portstar:BAABLgAECn8hAAMBAAkJbAvrbwCAAQABAAkJTgnrbwCAAQAcAAYJzQ2hDgDZAAAAAA==.Powwerbottom:BAAALgADCgIJAwAAAA==.',
Pr='Precast:BAAALgADCgUJCgAAAA==.Prestoresto:BAAALgAECgEJAQAAAA==.Prieske:BAABLgAECn8rAAQSAAcJ3R1sEQA+AgASAAcJQB1sEQA+AgAaAAUJ+RmUSAAXAQADAAQJtBfDOgAFAQAAAA==.Primed:BAABLgAECn9GAAImAAkJ9BZ+CAAlAgAmAAkJ9BZ+CAAlAgAAAA==.Privm:BAABLgAFFH8FAAIOAAUJAgfIIwD7AAAOAAUJAgfIIwD7AAAAAA==.Privxd:BAABLgAFFH8IAAIPAAQJwBj8CQA5AQAPAAQJwBj8CQA5AQAAAA==.Prunesa:BAAALgADCgcJBQAAAA==.',
Pu='Pungla:BAAALgAECggJDwAAAA==.',
['Pî']='Pîper:BAAALgADCgYJBwAAAA==.',
['Pï']='Pït:BAAALgAECggJEAAAAA==.',
Qp='Qprawindfury:BAAALgAECgYJEgAAAA==.',
Qu='Quadtwat:BAAALgAECgQJBwAAAA==.Quahogger:BAAALgAECgYJEQAAAA==.Quazer:BAAALgAECgEJAgAAAA==.Quelthanos:BAAALgAECgIJAgAAAA==.',
Ra='Radical:BAAALgAECggJDAAAAA==.Railyard:BAAALgADCgMJAwABLgAECgIJAgAHAAAAAA==.Raivn:BAAALgADCgEJAQAAAA==.Rajasta:BAAALgAECgQJCQAAAA==.Rajkwit:BAAALgADCgcJCwAAAA==.Rajzova:BAAALgADCgcJCgABLgAECgkJIAAWANkIAA==.Randomclown:BAAALgAECgYJCgAAAA==.Rapi:BAAALgAECgMJAwAAAA==.Rascalfats:BAABLgAECn8YAAIBAAYJEw/bqAARAQABAAYJEw/bqAARAQAAAA==.Rashii:BAABLgAECn8VAAIaAAkJ4BXiEwAhAgAaAAkJ4BXiEwAhAgAAAA==.Rawor:BAABLgAECn8qAAMYAAgJnRYyBwDfAQAYAAgJMRUyBwDfAQATAAcJSBISbgBUAQAAAA==.',
Re='Rebaderchi:BAACLgAFFH8VAAIEAAUJ1A3aQAALAQAEAAUJ1A3aQAALAQAuAAQKfzQAAgQACQktHXQaAGICAAQACQktHXQaAGICAAAA.Relyne:BAAALgADCgYJBgAAAA==.Remo:BAAALgAECgMJAwAAAA==.Remoria:BAAALgAECggJCgAAAA==.Rendaye:BAAALgAFFAEJAgAAAA==.Renildan:BAAALgAECgYJDwAAAA==.Renscope:BAAALgAECgcJAQAAAA==.Resala:BAAALgADCgYJBgAAAA==.Rev:BAAALgADCgMJAwAAAA==.Revanhawk:BAAALgADCgkJEQAAAA==.Revna:BAAALgADCgcJBwAAAA==.Rezputan:BAACLgAFFH8KAAMpAAMJnhPCDwDfAAApAAMJtxLCDwDfAAAZAAIJJA/gxACFAAAuAAQKfyMAAykACQmJH80CAKYCACkACQmOHs0CAKYCABkACAmJGHJQAL8BAAAA.',
Rh='Rholand:BAABLgAECn8gAAMKAAgJgx9eFAA6AgAKAAgJgx9eFAA6AgAlAAQJNRfONwB+AAAAAA==.Rhovid:BAAALgAECgEJAQAAAA==.',
Ri='Rind:BAAALgAECgYJCQAAAA==.Rioken:BAABLgAECn8hAAMTAAkJmhenLQAWAgATAAkJmhenLQAWAgAnAAEJgxCAbgA4AAAAAA==.Riolobo:BAAALgADCggJCAAAAA==.Riorage:BAABLgAECn8kAAIeAAgJqxdXIwAgAgAeAAgJqxdXIwAgAgAAAA==.Ritz:BAAALgAECgEJAQAAAA==.Rizzoy:BAACLgAFFH8HAAIKAAMJtg8RLwDSAAAKAAMJtg8RLwDSAAAuAAQKf0IAAgoACAl7IFUOAHgCAAoACAl7IFUOAHgCAAAA.',
Ro='Rohoth:BAAALgAECgMJBQAAAA==.Rolaiya:BAAALgADCgYJBgAAAA==.Rollo:BAAALgAECgUJDgAAAA==.Rolor:BAAALgADCgYJBgAAAA==.Rookiefister:BAAALgAECgQJAwAAAA==.Ross:BAECLgAFFH8RAAIOAAUJ3CUvCQAkAgAOAAUJ3CUvCQAkAgAuAAQKfyUAAg4ABwlxJQcQAIMCAA4ABwlxJQcQAIMCAAAA.Rovyr:BAABLgAECn86AAQLAAkJJSFAAgBDAwALAAkJJSFAAgBDAwAQAAMJXwvgbQBmAAARAAEJuAHmRQAeAAAAAA==.',
Ru='Ruckabis:BAABLgAECn8iAAMeAAkJex/KGQBiAgAeAAkJex/KGQBiAgAgAAEJSwcsnwAnAAAAAA==.Rundeezyy:BAAALgADCgYJCQAAAA==.',
Ry='Ryllock:BAAALgAECgIJAgAAAA==.Rylos:BAACLgAFFH8GAAIZAAMJ5AaalADEAAAZAAMJ5AaalADEAAAuAAQKfx4AAhkACAlTDURuAHQBABkACAlTDURuAHQBAAAA.Rytotem:BAAALgAECgQJCgAAAA==.Ryumi:BAAALgADCgkJCwAAAA==.Ryvington:BAAALgAECggJCAAAAA==.Ryvmonk:BAAALgADCgEJAQAAAA==.',
Sa='Saansula:BAAALgAECgUJDQAAAA==.Sabian:BAABLgAECn8iAAIkAAkJzhLFGwDSAQAkAAkJzhLFGwDSAQAAAA==.Saintjeb:BAACLgAFFH8FAAIdAAIJ5Ay4DgByAAAdAAIJ5Ay4DgByAAAuAAQKfxQAAh0ACAkDEtgXAFgBAB0ACAkDEtgXAFgBAAEuAAUUAwkEAAcAAAAA.Saitami:BAAALgAECgEJAQAAAA==.Saitamå:BAAALgAECgYJDAAAAA==.Sakisan:BAAALgAECgEJAgAAAA==.Salinity:BAABLgAECn8nAAMTAAkJmCIrBwAVAwATAAkJXCIrBwAVAwAnAAcJRSBvBwBRAgAAAA==.Samanaras:BAABLgAECn8VAAIiAAgJHBA1HABhAQAiAAgJHBA1HABhAQAAAA==.Sanari:BAAALgADCgMJAwAAAA==.Sangwyn:BAAALgAECgUJBQABLgAECggJJAAaAHoiAA==.Santiago:BAAALgAECgYJDwAAAA==.Saratoga:BAABLgAECn8YAAIbAAcJexoJXgDJAQAbAAcJexoJXgDJAQAAAA==.Sarkana:BAABLgAECn8kAAIjAAkJfB5WCQDiAgAjAAkJfB5WCQDiAgAAAA==.Sarticor:BAAALgAECgEJAQAAAA==.Sassquatch:BAACLgAFFH8FAAIZAAIJVQ5qrwCUAAAZAAIJVQ5qrwCUAAAuAAQKfyQAAxkABwlLGqBSALgBABkABwlLGqBSALgBAAkAAQkgBV9ZACMAAAAA.Satu:BAAALgADCgkJCQAAAA==.Saxonn:BAABLgAECn8oAAMgAAgJ+w3YNQBHAQAgAAgJ+w3YNQBHAQAeAAMJaQM5iABzAAAAAA==.Saydis:BAABLgAECn8XAAIGAAcJYAaGjwAFAQAGAAcJYAaGjwAFAQAAAA==.',
Sc='Schuftt:BAABLgAECn8UAAMcAAgJExooBACnAQAcAAgJExooBACnAQAhAAEJ9BQODgBGAAAAAA==.',
Se='Seafoodtower:BAAALgAECgEJAQAAAA==.Sebattan:BAAALgAECgcJEwAAAA==.Seleine:BAAALgAECgEJAQABLgAECgkJQAABAEAbAA==.Sello:BAAALgAECgEJAgAAAA==.Seltzers:BAAALgADCgQJCgAAAA==.Selunella:BAAALgADCgEJAQABLgAFFAEJAQAHAAAAAA==.Selvester:BAABLgAECn8lAAIIAAgJDiVjBQDbAgAIAAgJDiVjBQDbAgAAAA==.Senadria:BAABLgAECn8bAAIEAAUJtArNtgCYAAAEAAUJtArNtgCYAAAAAA==.Senseishifu:BAACLgAFFH8IAAIIAAQJBgz0KADzAAAIAAQJBgz0KADzAAAuAAQKfyEAAggACQk8FxEQACsCAAgACQk8FxEQACsCAAAA.Seorsen:BAAALgADCgcJEAAAAA==.Servinghunt:BAAALgAECgYJCwAAAA==.Sevalandre:BAAALgAECgEJAQABLgAECggJIgAZAFkYAA==.',
Sh='Shadowskyz:BAAALgADCgYJBgABLgAFFAUJEQACAFUNAA==.Shamatrest:BAAALgAECgEJAwABLgAECgkJKAAZAN4kAA==.Shamina:BAACLgAFFH8RAAICAAUJVQ2tBwAmAQACAAUJVQ2tBwAmAQAuAAQKfx0AAgIACAmHGU4JABACAAIACAmHGU4JABACAAAA.Shamite:BAAALgAECgMJAwABLgAECgkJEAAHAAAAAA==.Shammalin:BAABLgAECn8iAAMgAAgJ1Av0OwApAQAgAAgJ1Av0OwApAQAeAAUJlgxzdgDZAAAAAA==.Shamminator:BAAALgADCgMJAwAAAA==.Shamorex:BAABLgAECn80AAIgAAgJgxbpIQC8AQAgAAgJgxbpIQC8AQAAAA==.Shanoth:BAAALgAECgYJBwABLgAECggJIgAZAFkYAA==.Sharkbones:BAAALgAECgEJAQAAAA==.Shatter:BAAALgAECgcJDwAAAA==.Shax:BAAALgAECgUJBgABLgAECgkJJwATAJgiAA==.Shiftshappen:BAAALgAECgYJBwAAAA==.Shiftyy:BAAALgAECgcJCgAAAA==.Shogun:BAAALgADCgQJCAAAAA==.Shoopywoopy:BAAALgAECgEJAQAAAA==.Shteph:BAAALgAECgYJDAAAAA==.',
Si='Siaerosia:BAAALgADCgEJAQAAAA==.',
Sk='Skaarr:BAABLgAECn8VAAIKAAgJ3wiARgAUAQAKAAgJ3wiARgAUAQAAAA==.',
Sl='Slayn:BAABLgAECn8kAAIBAAgJFBGAZgCXAQABAAgJFBGAZgCXAQAAAA==.Sleinx:BAAALgADCgMJAwABLgAFFAYJFAAgAGQcAA==.Slowhealsboi:BAAALgAECgQJBAAAAA==.Slushpuppie:BAAALgADCgYJBgAAAA==.Slyrak:BAABLgAECn8yAAMRAAkJfhuaAgB8AgARAAkJfhuaAgB8AgALAAMJoQgQLwBcAAAAAA==.Slyva:BAAALgAECgMJAwAAAA==.',
Sm='Smithbruh:BAEALgAECgQJBAABLgAFFAMJBgAZALgWAA==.Smitus:BAAALgAECggJDQAAAA==.Smokescale:BAAALgADCgcJCAAAAA==.',
Sn='Snackie:BAABLgAECn8kAAIeAAgJih7hEACwAgAeAAgJih7hEACwAgAAAA==.Sneakyjewel:BAAALgADCgkJEAAAAA==.Snotpig:BAAALgAECggJBwAAAA==.',
So='Solarious:BAAALgAECgEJAQAAAA==.Sorscrasus:BAAALgADCgUJCAAAAA==.Soulcolektor:BAAALgADCgcJDwAAAA==.Souled:BAAALgAECgQJBQAAAA==.Sourpunchkid:BAAALgADCgQJBAAAAA==.',
Sp='Sparroh:BAAALgADCgEJAQAAAA==.Spikedriver:BAABLgAECn8kAAIGAAkJJxCKSACwAQAGAAkJJxCKSACwAQAAAA==.Spradwurd:BAAALgAECgUJCAAAAA==.',
Sq='Squee:BAABLgAECn8UAAMFAAgJuBXYKwBHAQAFAAgJuBXYKwBHAQAIAAEJ1wF4mQAaAAABLgAECggJFAAFALgVAA==.',
St='Stantonio:BAABLgAECn8UAAIcAAgJKwsBBwAoAQAcAAgJKwsBBwAoAQAAAA==.Stariane:BAABLgAECn8jAAINAAkJeh14CgBlAgANAAkJeh14CgBlAgAAAA==.Startaster:BAAALgAFFAEJAQAAAA==.Starvoid:BAAALgAECgEJAQAAAA==.Steaktartare:BAABLgAECn8lAAIjAAcJiA6dOQBNAQAjAAcJiA6dOQBNAQAAAA==.Steeldk:BAAALgAECgQJBQAAAA==.Steelfist:BAAALgAECgYJCgAAAA==.Steelpunch:BAAALgAECgUJCAAAAA==.Steelwill:BAAALgAECgIJAwAAAA==.Stonii:BAAALgAECgEJAQAAAA==.Stony:BAABLgAECn8tAAIGAAgJeyPMFACVAgAGAAgJeyPMFACVAgAAAA==.Stonyy:BAAALgAECgYJCwAAAA==.Stratpanda:BAAALgADCgkJCQAAAA==.Strelizia:BAAALgAECgIJAgAAAA==.Stressful:BAAALgADCgQJBAAAAA==.',
Su='Sub:BAABLgAFFH8GAAIoAAQJrQUFBwDwAAAoAAQJrQUFBwDwAAABLgAFFAYJHQACACckAA==.Suetekh:BAAALgADCgUJBQAAAA==.Sukidaiyo:BAABLgAECn8VAAIpAAgJQhaxCQC6AQApAAgJQhaxCQC6AQAAAA==.Summers:BAAALgAECgYJDgAAAA==.Sumonmyface:BAAALgAECgYJEAABLgAECgkJJgAUAMEQAA==.Sunshield:BAAALgAECgMJAwAAAA==.Superillbomb:BAAALgADCgcJDQAAAA==.Superold:BAAALgAECggJCAAAAA==.Suraug:BAAALgADCgcJBwAAAA==.Suzakku:BAAALgAECgQJBQAAAA==.',
Sw='Swampraught:BAABLgAECn8nAAMTAAgJ8BfqPADbAQATAAgJ8BfqPADbAQAnAAEJtA2ocAA1AAAAAA==.',
Sy='Syd:BAAALgADCgYJBgAAAA==.Syletage:BAAALgAECgMJBgAAAA==.Synd:BAAALgADCgEJAQAAAA==.Synrae:BAAALgAECggJBwAAAA==.Syral:BAAALgAECgUJCwAAAA==.Syrion:BAAALgAECgQJBAAAAA==.Sythrane:BAAALgAECgYJCgAAAA==.',
Ta='Taarii:BAAALgADCggJCAAAAA==.Talisoudwave:BAAALgAECgYJDQABLgAECggJIAAPABElAA==.Talomeo:BAAALgAECgIJAgAAAA==.Taradan:BAAALgAECgEJAQAAAA==.Taraxus:BAAALgADCgcJCwAAAA==.Tateraider:BAABLgAECn80AAMlAAkJvx0lBwB9AgAlAAkJvx0lBwB9AgAKAAEJQwualgAxAAAAAA==.Taterknight:BAAALgADCgkJCQAAAA==.Taurnator:BAAALgAECgMJBAAAAA==.Taylorswift:BAAALgAECgMJBgAAAA==.Tayven:BAAALgADCgEJAQAAAA==.',
Te='Tednougat:BAAALgADCgYJBgAAAA==.Telain:BAACLgAFFH8GAAIjAAIJwRehMACYAAAjAAIJwRehMACYAAAuAAQKf0wABCMACQlsF/ESAGUCACMACQlsF/ESAGUCABsABgkiFqRmAIgBAB0AAgmHFkI0AHYAAAAA.Tensuki:BAAALgAECgMJAwAAAA==.Teslah:BAAALgADCgQJBAAAAA==.',
Th='Thakilla:BAACLgAFFH8JAAIkAAMJLgfRLgCcAAAkAAMJLgfRLgCcAAAuAAQKfzMAAiQACQnOFdUTAB4CACQACQnOFdUTAB4CAAAA.Thanosonmage:BAAALgADCgcJBwAAAA==.Thavik:BAAALgADCgEJAwAAAA==.Theolodin:BAAALgAECgYJEQAAAA==.Thordrik:BAAALgAECgYJDAAAAA==.Thorix:BAABLgAECn8ZAAINAAkJGxRuEQD0AQANAAkJGxRuEQD0AQAAAA==.Thotmir:BAAALgAECgMJAwAAAA==.Thícc:BAAALgADCgkJCgAAAA==.',
Ti='Tigerburn:BAAALgADCgkJCgAAAA==.Tikibiki:BAAALgADCgMJAwAAAA==.Timbereses:BAAALgADCgUJBQAAAA==.Timberreaper:BAAALgAECgQJCAAAAA==.Tinyz:BAABLgAECn8cAAMaAAcJ8hMDIgCdAQAaAAcJ8hMDIgCdAQADAAUJTwbwVwCIAAAAAA==.',
To='Tolua:BAAALgAECgUJCAAAAA==.Tonata:BAABLgAECn8aAAMLAAkJCg+gGwAQAQALAAgJlQ2gGwAQAQAQAAkJBQuZPgAOAQAAAA==.Tonythetiger:BAAALgAECgEJAQABLgAECgkJOQAJAKQfAA==.Tootsie:BAAALgADCgYJEAAAAA==.Tormentus:BAAALgAECgMJAwAAAA==.',
Tr='Trampadin:BAAALgADCgkJCQAAAA==.Trenton:BAAALgADCgUJBwAAAA==.Trexlot:BAAALgAECgIJBgAAAA==.Trinjal:BAABLgAECn8uAAMOAAkJFRtMEACBAgAOAAkJFRtMEACBAgAFAAQJgxvcPAD0AAAAAA==.Trishift:BAAALgAECgQJBwAAAA==.Trueshru:BAAALgAECgIJAwAAAA==.',
Tu='Tubular:BAAALgAECgMJBQAAAA==.Tuskadin:BAACLgAFFH8JAAIbAAQJLRs+LwA2AQAbAAQJLRs+LwA2AQAuAAQKfyoAAhsACAlFJK4bAMQCABsACAlFJK4bAMQCAAAA.',
Tw='Tweeq:BAAALgAECgQJCQAAAA==.',
Ty='Tyjan:BAABLgAECn8UAAIbAAcJCQdwwADqAAAbAAcJCQdwwADqAAAAAA==.Tyrana:BAAALgAECgMJAwAAAA==.Tyriq:BAAALgADCgYJBgAAAA==.',
['Tã']='Tãz:BAAALgAECgEJAgAAAA==.',
Ul='Ulra:BAAALgADCgkJCgAAAA==.',
Un='Unclothed:BAABLgAECn8cAAImAAcJlwsQHAADAQAmAAcJlwsQHAADAQAAAA==.Unicorn:BAAALgADCggJCgAAAA==.Untòld:BAAALgADCggJCAABLgAECgcJGwABAJ4QAA==.',
Va='Valentine:BAAALgADCgIJAgAAAA==.Valitymage:BAAALgADCgEJAQAAAA==.Varthios:BAAALgAECgEJAgAAAA==.Varyusha:BAAALgAECgMJBAAAAA==.',
Ve='Velene:BAAALgADCgEJAQABLgAECgkJQAABAEAbAA==.Venzallow:BAAALgAECgUJBwAAAA==.Veralynn:BAAALgADCgcJBwAAAA==.Veravibes:BAAALgAECgQJCwAAAA==.Vermagnus:BAABLgAECn8iAAMIAAgJLxsXEAArAgAIAAgJLxsXEAArAgAFAAEJyA6OiAA2AAAAAA==.Vespor:BAABLgAECn8ZAAIPAAYJHR8XJgAKAgAPAAYJHR8XJgAKAgAAAA==.',
Vi='Viktorya:BAABLgAECn8eAAILAAcJGBedFgDlAQALAAcJGBedFgDlAQAAAA==.Vilelyn:BAABLgAECn8lAAMFAAgJbRfXFgDoAQAFAAgJbRfXFgDoAQAOAAIJURLxewBsAAABLgAECggJKwAbAHobAA==.Viloria:BAABLgAECn8qAAIfAAgJOxQ2FQCIAQAfAAgJOxQ2FQCIAQAAAA==.Vincent:BAAALgAECgQJBwAAAA==.Virrard:BAACLgAFFH8GAAIGAAIJEBkpYACrAAAGAAIJEBkpYACrAAAuAAQKfy8AAwYACQmFG4QeAFkCAAYACQmFG4QeAFkCABUAAglgD6B1AGgAAAAA.Vitalyellow:BAAALgADCgYJBgAAAA==.',
Vl='Vladimor:BAABLgAECn8WAAITAAcJZxkMbABYAQATAAcJZxkMbABYAQAAAA==.Vladimyrr:BAABLgAECn8YAAIbAAkJERYeWQCoAQAbAAkJERYeWQCoAQAAAA==.',
Vo='Vodan:BAAALgADCgEJAQAAAA==.Voidplague:BAAALgAECgYJDQAAAA==.Voidscarred:BAAALgAECgQJEgAAAA==.Vozrezz:BAABLgAECn8lAAMFAAcJtCFWDgBMAgAFAAcJtCFWDgBMAgAIAAYJUhr1JQBsAQAAAA==.',
Vu='Vualake:BAAALgADCgcJDgAAAA==.',
Vy='Vyridian:BAAALgAECgQJAwABLgAECgYJEwAHAAAAAA==.',
['Vë']='Vëda:BAABLgAECn8kAAIaAAkJKxHvHADGAQAaAAkJKxHvHADGAQAAAA==.',
Wa='Wardragon:BAAALgADCgcJCwAAAA==.Warrwras:BAAALgADCgcJDgAAAA==.Wasical:BAAALgAECgQJBAAAAA==.',
Wh='Wheaties:BAAALgAECgcJDAABLgAECgkJOQAJAKQfAA==.',
Wi='Wicker:BAABLgAECn8vAAIfAAkJ/SGpAwDTAgAfAAkJ/SGpAwDTAgAAAA==.Wickievoker:BAAALgADCgkJCQABLgAECgkJLwAfAP0hAA==.Wintersprout:BAAALgADCgYJBgAAAA==.Wintin:BAAALgAECgEJAgAAAA==.Wiskey:BAAALgAECgYJCQAAAA==.Wiçker:BAAALgAECgYJDAABLgAECgkJLwAfAP0hAA==.',
Wo='Wolford:BAABLgAECn8aAAIPAAcJKhvGKAD6AQAPAAcJKhvGKAD6AQAAAA==.Woogie:BAAALgADCgYJCgAAAA==.Wordz:BAAALgAECgEJAgAAAA==.',
Wr='Wras:BAABLgAECn8oAAIJAAcJVB+MDQAXAgAJAAcJVB+MDQAXAgAAAA==.Wretched:BAAALgAECgcJBQAAAA==.',
Wy='Wyrnn:BAAALgADCgcJEAAAAA==.Wysstical:BAAALgAECgcJBwABLgAFFAYJHQACACckAA==.',
['Wò']='Wòbbles:BAAALgAECgYJEgABLgAECgYJGAABABMPAA==.',
Xa='Xalnova:BAAALgADCgYJDAAAAA==.Xandos:BAAALgAECgQJBgAAAA==.Xandrah:BAABLgAECn8gAAIDAAcJBghvQADpAAADAAcJBghvQADpAAAAAA==.Xanslash:BAABLgAECn8jAAIEAAkJwR0gGwBdAgAEAAkJwR0gGwBdAgAAAA==.Xari:BAACLgAFFH8dAAIBAAcJIhhIFwD3AQABAAcJIhhIFwD3AQAuAAQKfywAAgEACQl1IwcSADsDAAEACQl1IwcSADsDAAAA.',
Xh='Xhalo:BAAALgADCggJCAAAAA==.',
Xi='Xiansai:BAABLgAECn8fAAIDAAkJbxbrGQDaAQADAAkJbxbrGQDaAQAAAA==.Xiongwei:BAAALgAECgEJAgAAAA==.',
Ya='Yappey:BAACLgAFFH8GAAIIAAIJxx21OQCnAAAIAAIJxx21OQCnAAAuAAQKfx8AAggACAkXImQIAJwCAAgACAkXImQIAJwCAAAA.',
Ye='Yehni:BAACLgAFFH8FAAIaAAMJKSPJEAAjAQAaAAMJKSPJEAAjAQAuAAQKf0YAAxoACQmtJG8CAHADABoACQmtJG8CAHADAAMABgkyGHgpAGUBAAAA.',
Yo='Youthinasia:BAAALgAECgQJBAAAAA==.',
Ys='Ys:BAAALgAECgIJAgABLgAECgkJJAAaACsRAA==.',
Yu='Yurasick:BAAALgAECgYJCAAAAA==.',
Za='Zaesha:BAAALgADCggJCwAAAA==.Zalarii:BAAALgADCgEJAgAAAA==.Zarox:BAABLgAECn8eAAIZAAkJJBJ2UAC/AQAZAAkJJBJ2UAC/AQAAAA==.',
Ze='Zeroelement:BAABLgAECn8WAAIjAAgJPB+JMACBAQAjAAgJPB+JMACBAQAAAA==.',
Zi='Zimgir:BAAALgADCgEJAQAAAA==.',
Zo='Zombiehippo:BAABLgAECn8sAAIBAAkJTBtcKQBeAgABAAkJTBtcKQBeAgAAAA==.Zorcons:BAAALgAECgEJAQAAAA==.',
Zu='Zuuzuu:BAAALgADCgEJAQAAAA==.',
['Áu']='Áutarch:BAABLgAECn8ZAAIKAAgJYgpgPAA+AQAKAAgJYgpgPAA+AQAAAA==.',
['Èl']='Èlty:BAAALgAECgMJAwAAAA==.',
['Ðe']='Ðemøn:BAAALgAECgUJDwAAAA==.',
['Ðr']='Ðrexy:BAAALgADCgUJBQAAAA==.',
['Øg']='Øgar:BAAALgAECgEJAQAAAA==.',
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
