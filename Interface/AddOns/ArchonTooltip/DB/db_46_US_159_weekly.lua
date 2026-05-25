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

local lookup = {'Mage-Frost','Shaman-Enhancement','Priest-Shadow','DemonHunter-Devourer','Monk-Windwalker','Hunter-BeastMastery','Unknown-Unknown','Monk-Brewmaster','DeathKnight-Blood','Warrior-Fury','Evoker-Preservation','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Mistweaver','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Priest-Discipline','Warlock-Demonology','Hunter-Survival','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Unholy','Paladin-Retribution','Mage-Arcane','Paladin-Protection','Shaman-Restoration','Druid-Guardian','Shaman-Elemental','Mage-Fire','Warrior-Arms','Paladin-Holy','Druid-Balance','Warrior-Protection','Druid-Feral','Warlock-Affliction','Warlock-Destruction','Rogue-Outlaw','DeathKnight-Frost','Priest-Holy',}
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=46,date='2026-05-23',data={Ac='Acense:BAAALgAECgYJDAAAAA==.Acewing:BAAALgADCgkJCgAAAA==.Acidlock:BAAALgAECgEJAgAAAA==.Acidpriest:BAAALgAECggJDgAAAA==.Acidshaman:BAAALgADCgYJBwAAAA==.',
Ad='Adacey:BAAALgAECgcJDgAAAA==.Ademeo:BAAALgAFFAEJAQABLgAFFAYJIQABAOkUAA==.Adragon:BAAALgAECgcJDQAAAA==.Adrenalized:BAAALgADCgEJAQAAAA==.',
Ae='Aedryll:BAAALgAECgYJDQAAAA==.Aeriden:BAAALgAECgEJAQAAAA==.Aesuga:BAABLgAECn9AAAICAAkJEiZSAABsAwACAAkJEiZSAABsAwAAAA==.Aethelflaed:BAABLgAECn8mAAIDAAcJ3hvAGQDSAQADAAcJ3hvAGQDSAQAAAA==.',
Ag='Agnolotti:BAAALgAECgUJCAAAAA==.',
Ai='Aimedjupiter:BAAALgAECgYJEQABLgAFFAUJDAAEAMUYAA==.Air:BAAALgADCgcJBwABLgAECgkJGQAFAGoZAA==.Airlyn:BAABLgAECn8eAAIGAAcJ3gosagBAAQAGAAcJ3gosagBAAQAAAA==.Aisen:BAAALgADCgEJAQABLgAECgEJAQAHAAAAAA==.',
Ak='Aktras:BAAALgAECgUJDwAAAA==.',
Al='Alaunu:BAAALgAECgMJAwABLgAECgkJJwAIAPMIAA==.Aleas:BAAALgAECgQJCAAAAA==.Aliciab:BAAALgADCgYJEAAAAA==.Alkaid:BAAALgAECgEJAQAAAA==.Alndvia:BAAALgAECgcJEgAAAA==.Alponkster:BAAALgADCggJEwAAAA==.Alunia:BAAALgAECgMJBwAAAA==.Alytheal:BAAALgAECgEJAQABLgAECgkJIgAJAHAdAA==.',
Am='Americow:BAAALgAECgIJAgAAAA==.',
An='Anarky:BAABLgAECn8rAAIKAAgJ2QOASwDuAAAKAAgJ2QOASwDuAAAAAA==.Andarnah:BAAALgADCgQJBAAAAA==.Annunaki:BAAALgAECgIJAwAAAA==.Anthrfinpete:BAAALgAECgYJDQABLgAECgcJHwALANMUAA==.Anze:BAAALgAECgIJAgAAAA==.',
Ar='Arathenes:BAAALgADCgcJCQAAAA==.Araylen:BAAALgADCgEJAQAAAA==.Archae:BAAALgADCgcJEQAAAA==.Archdemon:BAABLgAECn8bAAMMAAkJABiGBABNAgAMAAkJABiGBABNAgANAAEJWRt5ZQBOAAAAAA==.Ariannette:BAAALgAECgMJAwAAAA==.Arilyn:BAAALgADCgMJAwAAAA==.Arkhanx:BAAALgAECgUJDAAAAA==.Artemisia:BAAALgAECgMJAwAAAA==.Artichoke:BAABLgAECn8cAAMNAAkJHhC+IgAnAQANAAcJohK+IgAnAQAEAAUJTAerpwCnAAAAAA==.',
As='Ashamane:BAAALgAECgMJAwABLgAECgUJDAAHAAAAAA==.Ashanara:BAAALgADCgEJAQABLgAECggJIgAOAOAQAA==.Asheril:BAAALgAECgIJAgAAAA==.Ashy:BAAALgADCgUJBQAAAA==.Astrov:BAABLgAECn8WAAMNAAgJShFtGQB9AQANAAgJShFtGQB9AQAEAAUJhAy6pwDBAAAAAA==.',
At='Athera:BAAALgADCggJCAAAAA==.',
Au='Auani:BAABLgAECn8sAAIPAAkJhCPQAgCHAwAPAAkJhCPQAgCHAwAAAA==.Augtistic:BAABLgAECn9BAAMQAAkJ+yNaAwAtAwAQAAkJ+yNaAwAtAwARAAMJwRfbKwC+AAAAAA==.Aurani:BAAALgAECgEJAQAAAA==.',
Aw='Awyeahdaddy:BAAALgADCgMJAwAAAA==.',
Ay='Ayanna:BAAALgADCgkJFQAAAA==.',
Az='Azale:BAAALgAECgMJAwAAAA==.Azazyl:BAAALgAECgEJAQAAAA==.Azimuth:BAAALgAECgYJBgAAAA==.Azulagos:BAAALgADCgYJBgAAAA==.Azzeus:BAABLgAECn8aAAMDAAgJKRmuFgDwAQADAAgJKRmuFgDwAQASAAEJmxMfVwAzAAAAAA==.',
Ba='Babyrinsjr:BAABLgAECn8iAAIGAAcJaxnqOADPAQAGAAcJaxnqOADPAQAAAA==.Baeyn:BAAALgAECgcJCwABLgAFFAMJBQATAA4VAA==.Bagel:BAACLgAFFH8KAAMGAAQJ3hWhJAA8AQAGAAQJ3hWhJAA8AQAUAAMJCAkYAwDMAAAuAAQKfyAABBQACAnIGmwgAHkBABQABwkJHGwgAHkBABUABQkBFy86AHgBAAYABgn9DFVVAGgBAAEuAAUUBQkbAAIAsyMA.Baile:BAAALgAECgEJAQAAAA==.Bakon:BAAALgAECgUJDAAAAA==.Balin:BAAALgADCgYJDgAAAA==.Ballerin:BAAALgADCggJDwABLgAECgYJDQAHAAAAAA==.Bamsplat:BAAALgADCgYJBgAAAA==.Barrada:BAABLgAECn8gAAIGAAcJ+Ay1ZwBFAQAGAAcJ+Ay1ZwBFAQAAAA==.Barricay:BAAALgAECgYJBwAAAA==.Bathroy:BAAALgADCgIJAgAAAA==.',
Be='Bearcane:BAAALgADCgUJBQABLgAFFAQJEwAEANQNAA==.Beardheals:BAAALgAECgQJBAAAAA==.Beardàddy:BAAALgAECgQJBQAAAA==.Bellamira:BAAALgADCgIJAgAAAA==.Benjarrey:BAAALgAECgUJCQAAAA==.Berea:BAABLgAECn8aAAIWAAgJngcFDABLAQAWAAgJngcFDABLAQAAAA==.',
Bi='Bigmeatyclaw:BAAALgAECgEJBAAAAA==.Billywitchdr:BAAALgADCgEJAQAAAA==.',
Bl='Blankdemonic:BAAALgAECgEJAQAAAA==.Bleedblue:BAABLgAECn8yAAIXAAgJ9xmyEAACAgAXAAgJ9xmyEAACAgAAAA==.Blueballmonk:BAAALgAECgYJCgAAAA==.Bluerare:BAABLgAECn83AAIBAAkJSxoMJQBrAgABAAkJSxoMJQBrAgAAAA==.',
Bo='Bobsgrundle:BAAALgAECgQJBAAAAA==.Bolty:BAAALgADCgUJBQAAAA==.Borahae:BAAALgAFFAIJBAAAAA==.Bowlinna:BAAALgAECgQJBwAAAA==.',
Br='Brewrosia:BAAALgAECgYJCgAAAA==.Briiki:BAAALgAECgEJAQAAAA==.Brinnohms:BAAALgAECgEJAQAAAA==.Broadsnatl:BAAALgADCgEJAQAAAA==.Bruddah:BAAALgADCgEJAQAAAA==.Brunnhild:BAAALgAECgUJCAAAAA==.Bryxi:BAAALgAECggJEQABLgAECggJIgAYAFkYAA==.Brünhilde:BAABLgAECn8sAAMSAAgJgBQ0HAC+AQASAAgJgBQ0HAC+AQADAAIJzQnbXQBhAAAAAA==.',
Bs='Bstbll:BAACLgAFFH8WAAIPAAcJTxEyCgD7AQAPAAcJTxEyCgD7AQAuAAQKfxYAAg8ACQmUHv4JAPQCAA8ACQmUHv4JAPQCAAAA.Bstwaves:BAAALgAECgQJBQAAAA==.',
Bu='Bubbleban:BAAALgADCgUJBQAAAA==.Bubbleheals:BAAALgAECgEJAQABLgAFFAUJDAACALMIAA==.Bungxi:BAAALgADCgUJBgABLgAECggJIgAYAFkYAA==.Buraddo:BAAALgAECgYJDgABLgAECgcJKgAZAC0cAA==.Burrata:BAAALgADCgkJCQAAAA==.Buttsnacks:BAABLgAECn8mAAIKAAkJOSE5CQCvAgAKAAkJOSE5CQCvAgAAAA==.',
Ca='Cairebear:BAAALgAECgUJCwAAAA==.Callistrah:BAABLgAECn8oAAMaAAgJhBVLAwDOAQAaAAgJhBVLAwDOAQABAAMJ4wWq+gCDAAAAAA==.Caltaa:BAABLgAECn9CAAIbAAkJSCXTAABEAwAbAAkJSCXTAABEAwAAAA==.Camael:BAAALgAECgcJDwAAAA==.Canarah:BAAALgADCgUJBQABLgAFFAQJDAAcAEsQAA==.Canverian:BAABLgAECn8iAAIdAAcJHRq9DgC7AQAdAAcJHRq9DgC7AQAAAA==.Carmedic:BAAALgADCgcJDQAAAA==.Carradine:BAAALgADCggJCQAAAA==.',
Ce='Celexa:BAAALgAECgkJDgABLgAECgQJEgAHAAAAAA==.Celtmon:BAAALgADCgIJAwAAAA==.',
Ch='Cha:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.Chapi:BAAALgAECgYJCQAAAA==.Chasseurfool:BAABLgAECn8UAAIGAAUJ9ww3mQDYAAAGAAUJ9ww3mQDYAAAAAA==.Chat:BAACLgAFFH8SAAIeAAUJQRrNFAA4AQAeAAUJQRrNFAA4AQAuAAQKfy8AAh4ACQk2GwgNAHICAB4ACQk2GwgNAHICAAAA.Chevalieono:BAAALgADCgIJAgAAAA==.Chewi:BAAALgADCgEJAQAAAA==.Chezaro:BAAALgAECgUJBgAAAA==.Chickenlitle:BAAALgADCgUJBQAAAA==.Chickenwing:BAABLgAECn8xAAIfAAgJ3B9bAQBuAgAfAAgJ3B9bAQBuAgAAAA==.Chilin:BAAALgAECgYJBwAAAA==.Chilinevoke:BAAALgAECgMJBAABLgAECgYJBwAHAAAAAA==.Christano:BAABLgAECn8cAAMbAAcJ+RZVGAAtAQAZAAcJrhFnhgBtAQAbAAUJoxtVGAAtAQAAAA==.Christhecold:BAABLgAECn8/AAMgAAkJ8xyLCwAIAgAgAAcJKRqLCwAIAgAKAAcJ4RcYOQDCAQAAAA==.Chrollo:BAABLgAECn8UAAICAAYJchUmEwBEAQACAAYJchUmEwBEAQAAAA==.Chronoknight:BAAALgADCgkJCQAAAA==.Chronson:BAAALgAECgIJAgAAAA==.Chunt:BAAALgAECgQJCQAAAA==.',
Cl='Clamscasino:BAAALgADCgIJAgABLgAECgcJHwAhAHcNAA==.Clarke:BAAALgADCgMJAwAAAA==.Closets:BAAALgAECgMJAwAAAA==.Cloudcrack:BAACLgAFFH8bAAIeAAcJ2BQmBwDbAQAeAAcJ2BQmBwDbAQAuAAQKfy8AAh4ACQlfH7wKAJECAB4ACQlfH7wKAJECAAAA.Clynt:BAAALgADCgIJAgAAAA==.',
Co='Cocoapuffs:BAAALgADCgIJAgABLgAECgkJMAAJABcfAA==.Cocotaso:BAAALgAFFAMJBAAAAA==.Codemon:BAABLgAECn8mAAMRAAcJ2BPyCwA0AQARAAYJSRbyCwA0AQAQAAcJtwwdOgAcAQAAAA==.Coldfusion:BAAALgADCgkJCgAAAA==.Condemn:BAAALgADCgEJAgAAAA==.Condiments:BAAALgAECgEJAgAAAA==.Cortar:BAAALgAECgkJDwAAAA==.Cotw:BAAALgAECgIJAgABLgAECgcJDQAHAAAAAA==.',
Cp='Cptcharis:BAAALgADCgYJBgAAAA==.',
Cu='Cubann:BAAALgAECgMJAwAAAA==.',
Cy='Cylrhea:BAABLgAECn8gAAMPAAgJESVMBQBMAwAPAAgJESVMBQBMAwAiAAIJ+AXhbQBDAAAAAA==.Cyntrill:BAAALgAECgUJDAAAAA==.',
Da='Dadderz:BAAALgAECgMJBAAAAA==.Daddydruid:BAAALgAECgQJBgAAAA==.Daemonyx:BAAALgADCgkJCQABLgAECgUJDAAHAAAAAA==.Dahunter:BAABLgAECn8YAAIUAAgJsBplDQA1AgAUAAgJsBplDQA1AgAAAA==.Dajoel:BAAALgAECgYJDQAAAA==.Dakinna:BAAALgADCgMJAwAAAA==.Dakotawolfe:BAAALgADCgUJBQAAAA==.Dalacia:BAABLgAECn8bAAIcAAgJbxPNOACbAQAcAAgJbxPNOACbAQAAAA==.Dannyrojas:BAAALgAECgEJAgAAAA==.Daphera:BAAALgAECggJCAAAAA==.Darkforceray:BAAALgAECgEJAQAAAA==.Darknature:BAABLgAECn8zAAMPAAkJchICKwDdAQAPAAkJchICKwDdAQAiAAcJmBDtNAATAQAAAA==.Darkodin:BAABLgAECn8lAAIYAAcJXguujwAgAQAYAAcJXguujwAgAQAAAA==.Darkomen:BAAALgADCgcJGQABLgAECggJLgAYAFYQAA==.Darkvlad:BAABLgAECn8uAAIYAAgJVhDPVwCaAQAYAAgJVhDPVwCaAQAAAA==.Datnagadrake:BAACLgAFFH8UAAMKAAUJ0xVTFwAxAQAKAAUJBhVTFwAxAQAjAAIJXxUVCwCWAAAuAAQKf0IAAwoACQn4I+sCACcDAAoACQn4I+sCACcDACMAAgldHlcsAK8AAAAA.Davere:BAAALgADCgEJAQAAAA==.Dawinchy:BAACLgAFFH8NAAIPAAQJfA4+JQAJAQAPAAQJfA4+JQAJAQAuAAQKf0QABA8ACQmIFEg0ANcBAA8ACQmIFEg0ANcBACQABwlyC58WACgBACIAAQmnBeOFACEAAAAA.',
Dc='Dchalla:BAAALgADCgcJDQAAAA==.',
De='Deadlypsycho:BAAALgAECgYJEgAAAA==.Deadmanrise:BAAALgADCgUJBQAAAA==.Deathawakens:BAABLgAFFH8IAAIXAAQJDgzGFwAqAQAXAAQJDgzGFwAqAQAAAA==.Deathlyill:BAAALgAECgYJEQAAAA==.Deathtouch:BAAALgADCgcJDAAAAA==.Decembër:BAABLgAECn8nAAIBAAgJUwdFjgA/AQABAAgJUwdFjgA/AQAAAA==.Decimious:BAAALgAECgQJBwAAAA==.Dekutree:BAABLgAECn8hAAMdAAgJqA5HHAAoAQAdAAgJqA5HHAAoAQAkAAEJsQP4RAAmAAAAAA==.Dellistia:BAAALgAECgUJDAAAAA==.Delvan:BAAALgAECgIJAgAAAA==.Demiglace:BAAALgAECgYJDgAAAA==.Demonkilla:BAAALgAECgYJDwAAAA==.Denadan:BAAALgAECgEJAQABLgAECggJLwAlAFcLAA==.Desdamona:BAABLgAECn8gAAIGAAgJNQVxdAAoAQAGAAgJNQVxdAAoAQAAAA==.Destrodeath:BAABLgAECn8WAAIYAAkJ3g4XQwDXAQAYAAkJ3g4XQwDXAQAAAA==.Destrodemon:BAABLgAECn8jAAIEAAgJEhIGVgBhAQAEAAgJEhIGVgBhAQAAAA==.Deviltango:BAAALgAECgQJBAAAAA==.Devorick:BAABLgAECn80AAMTAAkJPBvcGgBpAgATAAkJPBvcGgBpAgAmAAIJQxCqUQB5AAAAAA==.Deztaknee:BAAALgAECgMJBAAAAA==.',
Di='Diadem:BAAALgAECgMJBAABLgAFFAMJBQATAA4VAA==.Diathian:BAAALgAECgUJBwABLgAFFAYJIQABAOkUAA==.Diaval:BAABLgAECn8dAAIZAAYJbQbMygDVAAAZAAYJbQbMygDVAAAAAA==.Dih:BAAALgAECgIJAgABLgAECgkJJgAUAMEQAA==.Dihlngthepal:BAAALgAECgEJAQAAAA==.Dirtyzealot:BAAALgADCgkJFwAAAA==.Disenchanted:BAAALgAECgYJBgABLgAECggJGwAQAIcZAA==.Divineknight:BAAALgADCgkJFQAAAA==.Diyiya:BAAALgAECgYJCwAAAA==.',
Dk='Dkchex:BAAALgAECgQJBAAAAA==.',
Dn='Dnkys:BAAALgAECgQJBAAAAA==.',
Do='Dokoth:BAAALgADCgEJAQAAAA==.Doorki:BAAALgAFFAIJBAAAAA==.Doubleott:BAAALgAECgcJDwAAAA==.',
Dr='Drael:BAAALgAECgMJBgAAAA==.Dragonayre:BAAALgAECgUJCQABLgAFFAMJBQATAA4VAA==.Draickin:BAABLgAECn8mAAIhAAgJmxd8FwAmAgAhAAgJmxd8FwAmAgAAAA==.Drekle:BAAALgAECgcJEgAAAA==.Drelian:BAAALgAECgUJCgAAAA==.Drenzel:BAAALgADCgYJCQAAAA==.Drevy:BAABLgAECn8WAAQXAAcJHhYkJQA9AQAXAAcJHhYkJQA9AQAnAAMJOgiTDABdAAAWAAEJAADZJwAAAAAAAA==.Drewsguy:BAAALgAECgMJBgAAAA==.Drexchan:BAAALgAECgYJDwAAAA==.Drexen:BAAALgADCgQJBQAAAA==.Drexy:BAAALgAECgEJAQAAAA==.Drhoger:BAAALgAECgUJBwAAAA==.Dropdahammer:BAAALgADCgUJBQAAAA==.Drumma:BAAALgAECgQJBwAAAA==.Drumroleplz:BAABLgAECn8bAAMQAAgJhxleIwCeAQARAAUJWSCZEwCrAQAQAAcJjRReIwCeAQAAAA==.',
Ds='Dsanatrestk:BAABLgAECn8oAAMYAAkJ3iRJDwDTAgAYAAkJ3iRJDwDTAgAJAAcJ1RpaEAAFAgAAAA==.',
Du='Dumbman:BAAALgAECgcJCgABLgAECgkJJwATAJgiAA==.',
Dw='Dw:BAAALgADCgUJBQAAAA==.',
['Dà']='Dàddybear:BAABLgAECn8ZAAIGAAkJRBBOWABtAQAGAAkJRBBOWABtAQAAAA==.',
Ea='Earthsangel:BAAALgAECggJDgAAAA==.',
Ec='Eclair:BAABLgAFFH8MAAIbAAQJbhAlBgDuAAAbAAQJbhAlBgDuAAAAAA==.',
Ed='Edralyia:BAAALgAECgUJDAAAAA==.',
Ei='Eilaurosa:BAABLgAECn84AAIWAAkJ/BjQAwBCAgAWAAkJ/BjQAwBCAgAAAA==.',
El='Eldrinne:BAABLgAECn8UAAIfAAgJvQM6BwDxAAAfAAgJvQM6BwDxAAAAAA==.Elftuah:BAAALgADCggJCAAAAA==.Elfö:BAABLgAECn8VAAIGAAkJThXwNwDTAQAGAAkJThXwNwDTAQAAAA==.Elizawrath:BAABLgAECn80AAMbAAgJ3SJrBACQAgAbAAgJ3SJrBACQAgAhAAUJlBHkWgARAQAAAA==.Elkuco:BAAALgAECgIJAgAAAA==.Elthiss:BAABLgAECn80AAIdAAgJJBv9CQAMAgAdAAgJJBv9CQAMAgAAAA==.Elusuma:BAAALgAECgkJBwAAAA==.',
Em='Emariel:BAAALgAECgMJBwAAAA==.',
En='Enchäntress:BAACLgAFFH8HAAITAAMJdAIMcgCsAAATAAMJdAIMcgCsAAAuAAQKfx0AAxMACQkjDXpQAJMBABMACQkjDXpQAJMBACUAAQkAAIM3ACMAAAAA.Enfer:BAAALgADCgYJCAABLgAFFAUJEgAeAEEaAA==.Enogg:BAAALgAECgYJCQAAAA==.Envi:BAABLgAECn88AAMBAAkJuBn8KgBRAgABAAkJuBn8KgBRAgAaAAEJWRUrEABBAAAAAA==.',
Ep='Ephraìm:BAAALgAECgYJBgAAAA==.',
Er='Erianthe:BAABLgAECn8wAAIYAAkJWArNWgCSAQAYAAkJWArNWgCSAQAAAA==.Erophien:BAAALgADCgkJLAABLgAECgcJHAAUABsIAA==.Erovael:BAAALgADCgQJBAABLgAECgcJHAAUABsIAA==.Erovynael:BAABLgAECn8cAAMUAAcJGwgPKQA1AQAUAAcJGwgPKQA1AQAGAAQJeAMetQCbAAAAAA==.',
Ev='Eversong:BAAALgAECgYJEQAAAA==.Evhi:BAAALgAECgYJCQAAAA==.',
Ex='Exmar:BAAALgAECgMJAwAAAA==.',
Fa='Faewhisker:BAAALgADCgcJEQAAAA==.Falnor:BAAALgADCgkJDAABLgAECgkJKwADAHsaAA==.Famine:BAABLgAECn8kAAMYAAkJaBzyMQBwAgAYAAkJaBzyMQBwAgAoAAEJAABcMwAAAAAAAA==.Fancyfeet:BAAALgAECgcJDAABLgAFFAUJEgAXAIIXAA==.Fangmonarch:BAAALgADCgEJAQAAAA==.',
Fc='Fckmalfurion:BAAALgADCgkJCQABLgAECgkJJgAUAMEQAA==.',
Fe='Fearios:BAABLgAECn8wAAIJAAkJFx+jBQCtAgAJAAkJFx+jBQCtAgAAAA==.Febronia:BAAALgAECgUJBQAAAA==.Felbeast:BAAALgAECgYJBQAAAA==.Felbound:BAAALgAECgEJAQAAAA==.Felltheburn:BAAALgADCgEJAQAAAA==.',
Fi='Figmênt:BAAALgAECgUJDgABLgAECgcJHwAhAHcNAA==.Finatic:BAAALgAECgMJAwAAAA==.Finneous:BAABLgAECn8VAAQFAAcJWBpkGQC8AQAFAAcJGRpkGQC8AQAIAAEJQh1wbgBPAAAOAAEJlgM1mwAaAAAAAA==.Fireproof:BAABLgAECn8bAAMbAAcJjiKPCABPAgAbAAcJOiCPCABPAgAZAAcJyBv+OQA7AgAAAA==.Fistedwaffle:BAAALgAECgEJAQABLgAFFAMJBAAHAAAAAA==.Fistopher:BAAALgAECgEJAQAAAA==.',
Fj='Fjorskin:BAAALgAECgQJBAAAAA==.',
Fl='Flairdragin:BAAALgAECgYJDQAAAA==.Flare:BAAALgAECggJEgAAAA==.',
Fo='Forix:BAAALgADCggJDAAAAA==.',
Fr='Fries:BAAALgADCggJCAAAAA==.Frosttbyte:BAABLgAECn8dAAIBAAkJcBy9IwByAgABAAkJcBy9IwByAgAAAA==.Frostytute:BAAALgADCgcJEQAAAA==.Frozenwitch:BAAALgADCgUJBQAAAA==.',
Fu='Fullmetalass:BAAALgADCggJCAABLgAECgIJAgAHAAAAAA==.Funsies:BAAALgADCgEJAQAAAA==.',
Fy='Fyrrstorm:BAAALgAECgMJAwAAAA==.',
['Fë']='Fëiróx:BAAALgADCgYJBgAAAA==.',
Ga='Gallum:BAAALgADCgEJAQAAAA==.Gamuza:BAAALgAECgQJBAAAAA==.',
Ge='Getzi:BAABLgAECn8cAAIZAAkJ4CH8FQDlAgAZAAkJ4CH8FQDlAgAAAA==.',
Gh='Ghavinflip:BAABLgAECn8WAAIFAAgJyA+GIgByAQAFAAgJyA+GIgByAQAAAA==.',
Gi='Gil:BAABLgAECn83AAIEAAkJCyO1BQAZAwAEAAkJCyO1BQAZAwAAAA==.Gimlita:BAAALgAECgIJAgABLgAECggJIgAYAFkYAA==.Gindraxx:BAAALgADCgEJAQAAAA==.',
Gl='Glocket:BAAALgADCgEJAQAAAA==.',
Go='Goatspace:BAAALgADCgcJDgABLgAECggJLwAlAFcLAA==.Goettel:BAAALgAECgUJBQAAAA==.Gogmazios:BAAALgADCgEJAQAAAA==.Gogofisco:BAAALgAECgEJAgAAAA==.Gongagà:BAAALgAECgYJDAAAAA==.Goodnoodle:BAAALgADCgEJAQAAAA==.Goyum:BAAALgAECgQJBAAAAA==.',
Gr='Grankino:BAABLgAECn8gAAIkAAcJKRjLDAC1AQAkAAcJKRjLDAC1AQAAAA==.Grapenuts:BAAALgADCgEJAQABLgAECgkJMAAJABcfAA==.Grayves:BAAALgAECgUJBAAAAA==.Greenthumbs:BAABLgAECn8VAAIiAAcJVwjtPQDmAAAiAAcJVwjtPQDmAAAAAA==.Greyhulk:BAABLgAECn8XAAMYAAYJ/Q8eowD/AAAYAAYJ/Q8eowD/AAAJAAUJhwZ9OgB4AAAAAA==.Grinlock:BAAALgADCgEJAQAAAA==.',
Gu='Guldanshower:BAAALgADCgIJAgAAAA==.Gurni:BAAALgADCgYJCAAAAA==.Guthan:BAAALgAECgEJAQAAAA==.Guthild:BAAALgAECgIJAgAAAA==.',
Gw='Gwaelphypha:BAABLgAECn8iAAMYAAgJWRj9RAAmAgAYAAgJnBf9RAAmAgAJAAcJlBHbHQA2AQAAAA==.',
Ha='Hakarii:BAAALgADCgYJDAAAAA==.Halder:BAAALgAECgEJAQAAAA==.Halliax:BAAALgADCgYJBgABLgAFFAMJBQATAA4VAA==.Hamburglar:BAAALgADCgYJCAAAAA==.Hapkido:BAABLgAECn9DAAMOAAkJtySDAQCuAwAOAAkJtySDAQCuAwAFAAEJcgRqkwAkAAAAAA==.Hardsus:BAAALgAECgQJAwAAAA==.Hauwitzer:BAAALgAECgIJAgAAAA==.Hawfmave:BAAALgAECgcJEQAAAA==.',
He='Heals:BAAALgAECgMJAwAAAA==.Healthpotion:BAAALgAECgMJAwAAAA==.Heartbroken:BAAALgAECgkJBwAAAA==.Hecate:BAABLgAECn8aAAIZAAcJMwWVuQDuAAAZAAcJMwWVuQDuAAAAAA==.Heidnik:BAAALgAECgQJBAAAAA==.Helvetica:BAAALgADCggJDwAAAA==.Heretic:BAAALgAECgUJDAAAAA==.Hessdemon:BAAALgAECgUJBQAAAA==.',
Hi='Hillboy:BAAALgAFFAIJAwAAAA==.Hippiehulk:BAAALgAECgEJAQAAAA==.',
Ho='Holydes:BAAALgAECgMJBgABLgAECggJIAAGADUFAA==.Holyfrejoles:BAAALgAECgkJAwAAAA==.Holyshrimp:BAABLgAECn85AAIDAAkJIR6jBgDLAgADAAkJIR6jBgDLAgAAAA==.Honeydew:BAAALgAECgkJAQABLgAECgkJAgAHAAAAAA==.Hordor:BAAALgAECgEJAQAAAA==.Hotndot:BAAALgADCgcJCgAAAA==.',
Hu='Humboldt:BAAALgAECgEJAQAAAA==.Hummakavulä:BAAALgAECgUJDAAAAA==.Hunkahunka:BAAALgAECgMJBAAAAA==.Huunaron:BAABLgAECn8jAAMhAAgJNhmgIQDQAQAhAAgJNhmgIQDQAQAZAAQJUwfn3wC3AAABLgAECgkJGAASAOocAA==.',
Id='Idylwilde:BAAALgAECgYJEwAAAA==.',
Ie='Ienzo:BAAALgADCgUJBQAAAA==.',
If='Ifunny:BAAALgAECgcJCgAAAA==.',
Ih='Iheartoreos:BAABLgAECn8yAAMJAAgJKRTjFwB1AQAJAAgJFRTjFwB1AQAoAAQJLwnwDgCzAAAAAA==.',
Il='Illiblades:BAAALgAECgQJBAABLgAFFAUJFwANAP8hAA==.Ilovefuta:BAABLgAFFH8HAAIIAAMJ+BLiKwDZAAAIAAMJ+BLiKwDZAAAAAA==.',
In='Ineedoreos:BAAALgAECgMJAwAAAA==.Inferna:BAAALgADCgQJCgAAAA==.Infidelis:BAAALgAECgEJAQAAAA==.Ink:BAABLgAFFH8GAAIYAAMJfxbpOwClAAAYAAMJfxbpOwClAAAAAA==.Inmortuae:BAAALgAECgMJAwAAAA==.Instakill:BAAALgADCgYJCQAAAA==.Insulin:BAAALgADCgkJEgAAAA==.Invictae:BAABLgAECn8YAAQSAAcJsg4aKQBbAQASAAYJYxAaKQBbAQADAAYJRAelQgDaAAApAAQJwAyJRQCoAAAAAA==.',
Io='Iobo:BAACLgAFFH8RAAIEAAcJiBpUGACSAQAEAAcJiBpUGACSAQAuAAQKfxgAAgQACQl4Ig8HAFYDAAQACQl4Ig8HAFYDAAAA.',
Ir='Iradori:BAABLgAFFH8hAAIBAAYJ6RTeIQCbAQABAAYJ6RTeIQCbAQAAAA==.Irønbane:BAAALgAECgEJAQAAAA==.',
Is='Iskandar:BAAALgAECgYJCgAAAA==.Isparian:BAABLgAECn8sAAQZAAcJDho+XwCTAQAZAAcJcBg+XwCTAQAbAAUJLA6CJADAAAAhAAEJiwmAgwAqAAAAAA==.Issior:BAAALgAECgMJAwAAAA==.',
Ja='Jaegar:BAAALgADCgIJAgAAAA==.Jamal:BAAALgADCgkJGwAAAA==.Jarco:BAEBLgAFFH8PAAQGAAUJmR8vFQBrAQAGAAUJmR8vFQBrAQAUAAEJigTxKQBEAAAVAAEJAAD3LAAAAAAAAA==.Jasmyn:BAAALgADCgEJAQAAAA==.Jasseca:BAAALgADCggJCAABLgAECggJIgAYAFkYAA==.Java:BAABLgAECn8aAAITAAcJURFpaABVAQATAAcJURFpaABVAQAAAA==.',
Je='Jeandarc:BAAALgADCgkJCQAAAA==.',
Jo='Joedakilla:BAAALgAECgEJAQAAAA==.Jonorin:BAAALgADCgEJAQAAAA==.',
Js='Jshaman:BAABLgAECn8XAAMcAAYJ6wdaegCzAAAcAAUJ9QdaegCzAAAeAAYJMgPXXwCTAAAAAA==.',
Ju='Judoken:BAABLgAECn8VAAMXAAYJIAeDMgDeAAAXAAYJHAeDMgDeAAAWAAUJUwLnFACsAAAAAA==.Jupiterr:BAABLgAFFH8HAAMVAAMJvRk4EwAKAQAVAAMJvRk4EwAKAQAGAAEJkROkcwBLAAABLgAFFAUJDAAEAMUYAA==.',
Ka='Kaadra:BAAALgAECgEJAQAAAA==.Kaeldach:BAAALgAECgYJCwAAAA==.Kaelgen:BAAALgAECggJCwAAAA==.Kaelkin:BAAALgAECggJEwABLgAECgkJJwACAEAWAA==.Kaelthlar:BAAALgAECgIJAwAAAA==.Kaelun:BAAALgAECgQJBwABLgAECgkJJwACAEAWAA==.Kaelundrus:BAABLgAECn8nAAMCAAkJQBZJCgDfAQACAAgJTBhJCgDfAQAcAAYJkBkbOwCQAQAAAA==.Kainis:BAABLgAECn8ZAAIVAAYJLwfYGQC+AAAVAAYJLwfYGQC+AAAAAA==.Kairia:BAAALgADCgEJAQAAAA==.Kalvinakri:BAAALgADCgkJDgAAAA==.Karasana:BAAALgAECgQJBAAAAA==.Karmus:BAAALgAECgcJEgAAAA==.Kastaspella:BAABLgAECn8ZAAIBAAcJFA+dgABaAQABAAcJFA+dgABaAQAAAA==.Kau:BAAALgAECgYJDwAAAA==.Kawant:BAAALgAECgIJAwAAAA==.Kaylnee:BAABLgAECn8fAAIcAAcJXxIUPACMAQAcAAcJXxIUPACMAQAAAA==.',
Ke='Keadin:BAAALgAECgUJDQAAAA==.Kearra:BAAALgADCgkJCQAAAA==.Kehayne:BAAALgADCgQJBAAAAA==.Keilas:BAABLgAECn8UAAIkAAcJpRifDAC5AQAkAAcJpRifDAC5AQAAAA==.Kerro:BAAALgAECgIJAwAAAA==.Kerron:BAAALgADCgMJAwAAAA==.Keyes:BAACLgAFFH8lAAIIAAgJ2BiXAQD8AQAIAAgJ2BiXAQD8AQAuAAQKfycAAggACQlsIZ4GALICAAgACQlsIZ4GALICAAAA.Keylala:BAABLgAECn8lAAMmAAcJzBWzCQB9AQAmAAcJzBWzCQB9AQATAAIJTwSO/ABKAAAAAA==.',
Ki='Kiafera:BAAALgADCgMJAwAAAA==.Kibo:BAAALgAECgMJAwAAAA==.Kickenmage:BAAALgAECgMJBAABLgAECgYJDwAHAAAAAA==.Kickentail:BAAALgAECgYJDwAAAA==.Kidx:BAAALgAECgMJAwAAAA==.Kimjunggoon:BAAALgAECgEJAQAAAA==.Kimunkamuy:BAAALgAECgYJBgAAAA==.Kiraw:BAAALgAECgIJAwAAAA==.Kirisham:BAAALgAECgQJBAAAAA==.Kirlia:BAAALgAECgMJBgAAAA==.Kishenia:BAAALgAECgIJAgAAAA==.',
Kl='Kleanx:BAAALgADCgUJBQAAAA==.Klymax:BAAALgADCgUJBQAAAA==.',
Ko='Kongor:BAABLgAECn8oAAICAAgJ3BxrBwAmAgACAAgJ3BxrBwAmAgAAAA==.Korathazan:BAAALgADCgEJAQAAAA==.Korithelse:BAAALgAECgEJAQAAAA==.Korthea:BAAALgAECgIJAgAAAA==.',
Kr='Krispitreat:BAAALgAECgYJCwAAAA==.Kritnespears:BAAALgAECgcJEgAAAA==.Krobelus:BAABLgAECn85AAMZAAkJggxnXwCSAQAZAAkJggxnXwCSAQAhAAYJVQXpZADoAAAAAA==.Kryptik:BAAALgADCgEJAQAAAA==.',
Kv='Kvedaheillr:BAAALgAECgMJAwAAAA==.Kvedaroðull:BAAALgADCgYJBwAAAA==.Kvedathulr:BAAALgADCgYJBgAAAA==.',
Ky='Kyehole:BAAALgADCgQJBAAAAA==.Kyluna:BAAALgAECgEJAQAAAA==.',
['Kè']='Kères:BAAALgAECgYJDQAAAA==.Kèrónos:BAAALgAECgMJBgAAAA==.',
['Kì']='Kìllstheweak:BAABLgAECn8xAAMoAAkJGBDaCwBzAQAoAAkJVg/aCwBzAQAJAAYJ3QwPJwAGAQAAAA==.',
La='Lauralai:BAAALgAECgMJAwAAAA==.Lavendra:BAAALgADCgcJDwAAAA==.Lawkz:BAAALgAECgcJCAAAAA==.Layliah:BAACLgAFFH8cAAIiAAYJrSMoBQD3AQAiAAYJrSMoBQD3AQAuAAQKf0gAAiIACQlJJSEBAGoDACIACQlJJSEBAGoDAAAA.',
Le='Leafless:BAAALgAECgEJAQAAAA==.Leaftemplar:BAAALgADCgYJBgAAAA==.Leedragoon:BAAALgADCgMJAwAAAA==.Legaia:BAAALgADCgYJCQAAAA==.Legendknewl:BAAALgAECgIJAgAAAA==.Leilara:BAAALgADCgcJCwAAAA==.Lemmesapthat:BAAALgADCgEJAQAAAA==.Leviathonian:BAAALgAECgEJAgAAAA==.',
Li='Lightseeker:BAAALgAECgEJAQAAAA==.Lillinna:BAAALgADCgQJBAAAAA==.Lilthina:BAAALgADCgcJBwABLgAECgcJHwAcAF8SAA==.Lisithen:BAAALgADCgEJAQAAAA==.Littlespoon:BAAALgAECgQJBgAAAA==.',
Lo='Loafai:BAABLgAECn8vAAQlAAgJVwu3DgA7AQAlAAcJPAy3DgA7AQAmAAYJ/ge+GQC2AAATAAcJAgQb1QCwAAAAAA==.Lockrocks:BAABLgAECn8jAAITAAgJgRz9KQAaAgATAAgJgRz9KQAaAgAAAA==.Lockycharmz:BAAALgAECgMJAwABLgAECgkJMAAJABcfAA==.Lorcán:BAAALgAECgUJDAAAAA==.Lormazlezrax:BAACLgAFFH8MAAIcAAQJSxAFLAD7AAAcAAQJSxAFLAD7AAAuAAQKfyEAAhwABwmtHxUZAE0CABwABwmtHxUZAE0CAAAA.Lowlife:BAAALgAECgUJCAABLgAECgcJEgAHAAAAAA==.',
Lu='Luis:BAAALgAECgQJBAAAAA==.Lumaron:BAAALgADCgEJAgAAAA==.Lunamizka:BAAALgADCgIJAgAAAA==.Lunella:BAAALgAECgUJBgABLgAECgUJDwAHAAAAAA==.Lunethira:BAAALgAECgUJDwAAAA==.Lustdeeznuts:BAABLgAECn8XAAIeAAYJjRtsLQBgAQAeAAYJjRtsLQBgAQAAAA==.',
Ly='Lylat:BAAALgAECgIJAgAAAA==.',
['Ló']='Lórdelrond:BAAALgADCgUJCgAAAA==.',
['Lú']='Lúpo:BAAALgAECgYJDQAAAA==.',
Ma='Machezemo:BAACLgAFFH8KAAIBAAMJhhYbYAD2AAABAAMJhhYbYAD2AAAuAAQKfx8AAgEACAn7Hp1HAOkBAAEACAn7Hp1HAOkBAAAA.Madhatter:BAAALgAECgUJBwAAAA==.Mahalka:BAAALgAECgEJAQAAAA==.Maki:BAABLgAECn8gAAIpAAcJsCMSCQC0AgApAAcJsCMSCQC0AgAAAA==.Malegar:BAAALgADCgkJIQAAAA==.Malendor:BAABLgAECn8zAAIFAAkJmSabAAB5AwAFAAkJmSabAAB5AwAAAA==.Mammajamma:BAAALgAECgEJAwABLgAECgQJBgAHAAAAAA==.Manbearcat:BAAALgAECgYJDQAAAA==.Marcydaghoul:BAAALgADCgUJBQAAAA==.Marivoker:BAAALgAECgMJBgABLgAECgYJCwAHAAAAAA==.Marsvolta:BAAALgADCgYJBgAAAA==.Maruxus:BAABLgAECn80AAMWAAkJLxnqAgBxAgAWAAkJLxnqAgBxAgAnAAYJfg9MBgBhAQAAAA==.Marvilla:BAAALgAECgkJEgAAAA==.Marwen:BAAALgAECgMJBgAAAA==.Mathbrew:BAEBLgAECn8hAAIIAAgJzCEQDwArAgAIAAgJzCEQDwArAgAAAA==.Mathbruh:BAEALgAECgEJAQABLgAECggJIQAIAMwhAA==.Maulsin:BAAALgAECgcJDAAAAA==.',
Mc='Mcchicken:BAAALgADCgIJAgAAAA==.Mclardragos:BAABLgAECn8eAAILAAgJlh0TBwBqAgALAAgJlh0TBwBqAgAAAA==.',
Me='Mecharoni:BAAALgAECgEJAQABLgAECgkJQQAQAPsjAA==.Medreaux:BAAALgAECgkJAgAAAA==.Mehv:BAEALgAECgkJCwAAAQ==.Melindria:BAABLgAECn8iAAMiAAgJjQuBPwA0AQAiAAYJHw+BPwA0AQAdAAgJawSjMQCbAAABLgAECgkJFwAcAG4WAA==.Mendicine:BAABLgAECn8fAAIPAAgJkBtHFACGAgAPAAgJkBtHFACGAgAAAA==.Menmoe:BAAALgAECgEJAQAAAA==.',
Mf='Mfdoom:BAAALgAECgMJAwAAAA==.',
Mi='Miacyn:BAAALgAECgYJDAAAAA==.Miladybast:BAABLgAECn8mAAIBAAcJjgT8wQDpAAABAAcJjgT8wQDpAAAAAA==.Miniwheet:BAAALgAECgYJBgABLgAECgkJMAAJABcfAA==.Mirra:BAABLgAECn8fAAIGAAgJpAvwWABrAQAGAAgJpAvwWABrAQAAAA==.Misha:BAAALgADCgUJBQAAAA==.Missdorei:BAAALgAECgUJCAAAAA==.',
Mo='Mogged:BAABLgAECn8rAAIBAAgJICHuGwCZAgABAAgJICHuGwCZAgAAAA==.Mojocity:BAAALgADCgYJCwAAAA==.Molai:BAAALgAECgcJBAAAAA==.Monkdangit:BAAALgAECgYJCQAAAA==.Mordraidas:BAAALgADCgkJCQAAAA==.Morionso:BAABLgAECn8qAAIbAAcJdR7uCgDuAQAbAAcJdR7uCgDuAQAAAA==.Morphyrinsjr:BAAALgADCgcJEgABLgAECgcJIgAGAGsZAA==.Mortarion:BAABLgAECn86AAIYAAkJNCFwCwDzAgAYAAkJNCFwCwDzAgAAAA==.Moxxulae:BAAALgADCgkJCAAAAA==.Moõn:BAABLgAECn8oAAIQAAkJTRBcHwC6AQAQAAkJTRBcHwC6AQAAAA==.',
Mu='Murcié:BAABLgAECn8pAAMEAAgJLxakOAASAgAEAAgJLxakOAASAgANAAYJHwkQOgAZAQAAAA==.Murdiûs:BAABLgAECn8kAAIOAAkJ7RukEABoAgAOAAkJ7RukEABoAgAAAA==.',
My='Myaliki:BAAALgADCgcJBwABLgAECgQJBAAHAAAAAA==.Myregards:BAAALgADCgYJBwAAAA==.Myspaceshria:BAAALgAECgUJDgABLgAECggJIgAYAFkYAA==.Mythbruh:BAEBLgAECn8eAAMYAAgJjCEiJABSAgAYAAgJZyAiJABSAgAJAAcJlSEvCwAuAgABLgAECggJIQAIAMwhAA==.Mythis:BAAALgAECgMJBAAAAA==.',
['Mó']='Mósh:BAAALgAECgYJBgAAAA==.',
Na='Nahane:BAAALgAECgQJBAAAAA==.Nahlur:BAAALgAECgMJAwAAAA==.Naoko:BAAALgAECgEJAgAAAA==.Natani:BAAALgADCgkJEQAAAA==.Nayrlock:BAACLgAFFH8FAAITAAMJDhUbXADgAAATAAMJDhUbXADgAAAuAAQKfyoABBMACQkTIEkaALcCABMACQkTIEkaALcCACUABQm1F18RABcBACYABAm4EKRAALIAAAAA.Nayuta:BAAALgADCgYJBQAAAA==.Nazal:BAAALgADCgEJAQABLgADCgEJAQAHAAAAAA==.',
Nc='Nc:BAAALgAECgEJAQAAAA==.Nctee:BAABLgAECn8UAAIBAAcJuRQEgQBZAQABAAcJuRQEgQBZAQAAAA==.',
Ne='Necrodwarf:BAAALgADCgEJAQAAAA==.Necropally:BAAALgAECgMJAwAAAA==.Necrotizor:BAABLgAECn8iAAMTAAgJwRrrLgAFAgATAAgJwRrrLgAFAgAmAAEJNBUsMwA4AAAAAA==.Neonsalmandr:BAAALgAECgEJAQAAAA==.Nerfhammer:BAAALgADCgIJAgAAAA==.Nerrol:BAAALgADCgkJCQAAAA==.',
Ni='Nialliv:BAAALgADCgcJCQAAAA==.Nidvin:BAABLgAECn8bAAIcAAYJURwCLADaAQAcAAYJURwCLADaAQAAAA==.Nightsmoke:BAAALgAECgQJBQAAAA==.Nixa:BAAALgADCgUJBQAAAA==.',
Nk='Nkb:BAAALgAECgYJDAAAAA==.',
Nn='Nnoitra:BAAALgADCgcJBwAAAA==.',
No='Noceman:BAAALgADCgEJAQAAAA==.Nock:BAAALgAECggJDwAAAA==.Nogg:BAAALgAECgEJAQAAAA==.Nolanel:BAAALgAECgYJBwAAAA==.Noll:BAAALgADCgUJBQAAAA==.Nonattarius:BAAALgAECgYJCwAAAA==.Norezfou:BAABLgAECn86AAMpAAkJKyBZCwCaAgApAAkJKyBZCwCaAgADAAQJwhj5OgD+AAAAAA==.Nornir:BAAALgAECgIJAgAAAA==.Norran:BAABLgAECn8bAAMDAAgJGRimGwDBAQADAAgJGRimGwDBAQASAAYJvBnGHwCgAQAAAA==.Norvera:BAAALgAECgIJAgAAAA==.Notalice:BAAALgAECgYJBwAAAA==.Notmywife:BAAALgAECgYJDQAAAA==.Novakri:BAAALgADCgMJAwABLgADCgYJDAAHAAAAAA==.',
Nu='Nuker:BAABLgAECn8dAAIBAAgJkwf2hgBNAQABAAgJkwf2hgBNAQAAAA==.Nurobi:BAABLgAECn8fAAIiAAgJkhRaIwCBAQAiAAgJkhRaIwCBAQAAAA==.Nuundix:BAABLgAECn8WAAIeAAgJhweyPgAJAQAeAAgJhweyPgAJAQAAAA==.',
Ny='Nysel:BAAALgAECgkJAQAAAA==.Nysera:BAAALgADCggJCAAAAA==.Nyxy:BAAALgAECgUJDAAAAA==.',
Oc='Ocey:BAAALgAECgEJAQABLgAECggJFAAPAN0ZAA==.',
Od='Odyn:BAABLgAECn8gAAIZAAgJ5RerQwDcAQAZAAgJ5RerQwDcAQAAAA==.',
Oo='Ooyu:BAAALgAECgUJCwAAAA==.',
Or='Orangepeel:BAAALgADCgUJBQAAAA==.Oridk:BAAALgAFFAEJAQABLgAFFAUJEwAUANYdAA==.Orimage:BAAALgADCgkJDAABLgAFFAUJEwAUANYdAA==.Oripal:BAAALgAECgUJBQABLgAFFAUJEwAUANYdAA==.Orisham:BAAALgADCgkJCQABLgAFFAUJEwAUANYdAA==.Oríon:BAACLgAFFH8TAAIUAAUJ1h3VBwBuAQAUAAUJ1h3VBwBuAQAuAAQKfyMAAxQACAkQJLsFALECABQACAkQJLsFALECABUABQlqFgtTAAABAAAA.',
Ou='Outofmyele:BAAALgADCgQJBAAAAA==.',
Ow='Owoker:BAABLgAECn8WAAIRAAgJJRqgBQDhAQARAAgJJRqgBQDhAQAAAA==.',
Pa='Pablo:BAABLgAECn8VAAIkAAcJ3xl8CwAHAgAkAAcJ3xl8CwAHAgAAAA==.Pancaked:BAAALgAECgEJAQABLgAFFAUJGwACALMjAA==.Pancakedup:BAAALgAECgcJDAABLgAFFAUJGwACALMjAA==.Pandozer:BAAALgAECggJEgAAAA==.Pankratos:BAABLgAECn8WAAMIAAkJliOyFABoAgAIAAkJliOyFABoAgAFAAMJLyDKNgD7AAAAAA==.Papaspud:BAABLgAECn8zAAIpAAkJ3A/HHgCqAQApAAkJ3A/HHgCqAQAAAA==.Paradias:BAACLgAFFH8SAAIXAAUJgheAEwBFAQAXAAUJgheAEwBFAQAuAAQKfy4AAxcACAm2IPYMAMoCABcACAmaIPYMAMoCABYABgmxFzEMAGIBAAAA.Pastor:BAAALgAECgYJEAAAAA==.Patpat:BAAALgADCgcJBgAAAA==.Paxxfist:BAABLgAECn8iAAIOAAgJ+RIBJQCxAQAOAAgJ+RIBJQCxAQAAAA==.',
Pe='Peachdevil:BAAALgAECgEJAQAAAA==.Penryn:BAAALgAECgEJAQAAAA==.Pentive:BAACLgAFFH8JAAIkAAMJeiAlBgAoAQAkAAMJeiAlBgAoAQAuAAQKfxcAAiQACAnLGzkFAL0CACQACAnLGzkFAL0CAAAA.Peppersgotem:BAAALgAECgEJAQAAAA==.Peppersham:BAABLgAECn8iAAMeAAcJiBkxHwC8AQAeAAcJiBkxHwC8AQAcAAIJVxkVgQCPAAAAAA==.Pepromene:BAAALgADCgUJBQAAAA==.Perff:BAAALgADCgYJBQAAAA==.Perhaps:BAACLgAFFH8FAAIIAAMJ4SAlHAAgAQAIAAMJ4SAlHAAgAQAuAAQKfxwAAggACAkbIokHAA0DAAgACAkbIokHAA0DAAAA.Persephone:BAAALgADCgYJBgAAAA==.Petesdragin:BAABLgAECn8fAAILAAcJ0xSzDgC+AQALAAcJ0xSzDgC+AQAAAA==.',
Pf='Pfftpfft:BAABLgAECn8VAAIGAAgJsR0GHgBIAgAGAAgJsR0GHgBIAgAAAA==.',
Ph='Phatdanny:BAABLgAECn8VAAIZAAgJcBi6SwDFAQAZAAgJcBi6SwDFAQAAAA==.Phatdumpy:BAABLgAECn8mAAQUAAkJwRDYFQDYAQAUAAkJbA3YFQDYAQAGAAcJcRO0OgDEAQAVAAQJ7wr/XADOAAAAAA==.Phattphatt:BAABLgAECn8bAAIkAAcJEBoJDQCxAQAkAAcJEBoJDQCxAQAAAA==.Phonycheese:BAABLgAECn8UAAMZAAgJkQ5NpgA0AQAZAAYJORNNpgA0AQAhAAMJuRedYgB4AAAAAA==.Phur:BAABLgAFFH8LAAIgAAMJIR8bEgALAQAgAAMJIR8bEgALAQAAAA==.',
Pi='Pinbal:BAAALgAECgQJBAAAAA==.Pixen:BAABLgAECn8qAAITAAgJgBdZNADvAQATAAgJgBdZNADvAQAAAA==.',
Pl='Plagueiss:BAABLgAECn8cAAIYAAgJjhrPPABEAgAYAAgJjhrPPABEAgAAAA==.',
Po='Pocalypse:BAAALgAECgYJBQAAAA==.Pocketsand:BAAALgADCgYJDAAAAA==.Ponkeylips:BAACLgAFFH8KAAIKAAUJZhk3EQBNAQAKAAUJZhk3EQBNAQAuAAQKfxoAAwoACAnaH/wKAJQCAAoACAnaH/wKAJQCACAAAQnNBsNDADEAAAAA.Portstar:BAABLgAECn8hAAMBAAkJbAsXYwCcAQABAAkJTgkXYwCcAQAaAAYJzQ2hDgDZAAAAAA==.Powwerbottom:BAAALgADCgIJAwAAAA==.',
Pr='Precast:BAAALgADCgUJCgAAAA==.Prestoresto:BAAALgAECgEJAQAAAA==.Prieske:BAABLgAECn8kAAQSAAYJpR7fFgDxAQASAAYJmh3fFgDxAQApAAUJ+RmUSAAXAQADAAQJtBc2NwAQAQAAAA==.Primed:BAABLgAECn9CAAIkAAkJthaNBwAtAgAkAAkJthaNBwAtAgAAAA==.Privm:BAAALgAECgMJAwAAAA==.Privxd:BAABLgAFFH8IAAIPAAQJwBj8CQA5AQAPAAQJwBj8CQA5AQAAAA==.Prunesa:BAAALgADCgcJBQAAAA==.',
Pu='Pungla:BAAALgAECggJDgAAAA==.',
['Pî']='Pîper:BAAALgADCgYJBwAAAA==.',
['Pï']='Pït:BAAALgAECggJEAAAAA==.',
Qp='Qprawindfury:BAAALgAECgYJEgAAAA==.',
Qu='Quadtwat:BAAALgAECgQJBwAAAA==.Quahogger:BAAALgAECgYJEQAAAA==.Quazer:BAAALgAECgEJAgAAAA==.',
Ra='Radical:BAAALgAECggJCwAAAA==.Railyard:BAAALgADCgMJAwABLgAECgIJAgAHAAAAAA==.Raivn:BAAALgADCgEJAQAAAA==.Rajasta:BAAALgAECgQJCQAAAA==.Rajkwit:BAAALgADCgYJBgAAAA==.Rajzova:BAAALgADCgcJCgABLgAECggJGgAWAJ4HAA==.Randomclown:BAAALgAECgYJCgAAAA==.Rapi:BAAALgAECgMJAwAAAA==.Rascalfats:BAABLgAECn8WAAIBAAYJEw+RnwAiAQABAAYJEw+RnwAiAQAAAA==.Rashii:BAABLgAECn8UAAIpAAgJ+BZxFgD3AQApAAgJ+BZxFgD3AQAAAA==.Rawor:BAABLgAECn8mAAMlAAcJlhRMEQAXAQATAAcJSBLNZQBbAQAlAAUJSBVMEQAXAQAAAA==.',
Re='Rebaderchi:BAACLgAFFH8TAAIEAAQJ1A0SOAAWAQAEAAQJ1A0SOAAWAQAuAAQKfzQAAgQACQktHfEXAGoCAAQACQktHfEXAGoCAAAA.Relyne:BAAALgADCgYJBgAAAA==.Remo:BAAALgAECgMJAwAAAA==.Remoria:BAAALgAECggJCQAAAA==.Rendaye:BAAALgAFFAEJAQAAAA==.Renildan:BAAALgAECgYJDwAAAA==.Renscope:BAAALgAECgcJAQAAAA==.Resala:BAAALgADCgYJBgAAAA==.Rev:BAAALgADCgMJAwAAAA==.Revanhawk:BAAALgADCgkJEQAAAA==.Revna:BAAALgADCgcJBwAAAA==.Rezputan:BAACLgAFFH8HAAMoAAMJqBK1DADjAAAoAAMJwRG1DADjAAAYAAIJJA/yrACOAAAuAAQKfyIAAygACAnzIMsDAF8CACgACAnVH8sDAF8CABgACAmJGKJJAMMBAAAA.',
Rh='Rholand:BAABLgAECn8dAAMKAAgJgx+gEQBGAgAKAAgJgx+gEQBGAgAjAAQJNRfnMwCCAAAAAA==.',
Ri='Rind:BAAALgAECgYJCQAAAA==.Rioken:BAABLgAECn8hAAMTAAkJmheHKQAcAgATAAkJmheHKQAcAgAmAAEJgxCAbgA4AAAAAA==.Riolobo:BAAALgADCggJCAAAAA==.Riorage:BAABLgAECn8fAAIcAAcJzRhpJwD0AQAcAAcJzRhpJwD0AQAAAA==.Ritz:BAAALgAECgEJAQAAAA==.Rizzoy:BAACLgAFFH8GAAIKAAMJKQ8DKgDRAAAKAAMJKQ8DKgDRAAAuAAQKf0IAAgoACAl7IHEMAIACAAoACAl7IHEMAIACAAAA.',
Ro='Rohoth:BAAALgAECgMJBQAAAA==.Rolaiya:BAAALgADCgYJBgAAAA==.Rollo:BAAALgAECgUJDQAAAA==.Rolor:BAAALgADCgYJBgAAAA==.Rookiefister:BAAALgAECgQJAwAAAA==.Ross:BAECLgAFFH8KAAIOAAUJfCMbCwDfAQAOAAUJfCMbCwDfAQAuAAQKfyAAAg4ABgmnJcgOAGoCAA4ABgmnJcgOAGoCAAAA.Rovyr:BAABLgAECn82AAQLAAkJJSH8AQBGAwALAAkJJSH8AQBGAwAQAAMJXwt9YgCBAAARAAEJuAHmRQAeAAAAAA==.',
Rs='Rsnakedawg:BAAALgADCgIJAgAAAA==.',
Ru='Ruckabis:BAABLgAECn8iAAMcAAkJex/wFgBlAgAcAAkJex/wFgBlAgAeAAEJSwe/kgAnAAAAAA==.Rundeezyy:BAAALgADCgYJCQAAAA==.',
Ry='Ryllock:BAAALgAECgIJAgAAAA==.Rylos:BAABLgAECn8eAAIYAAgJUw3nZQB3AQAYAAgJUw3nZQB3AQAAAA==.Rytotem:BAAALgAECgQJCgAAAA==.Ryumi:BAAALgADCgkJCwAAAA==.Ryvington:BAAALgAECggJCAAAAA==.Ryvmonk:BAAALgADCgEJAQAAAA==.',
Sa='Saansula:BAAALgAECgUJDQAAAA==.Sabian:BAABLgAECn8iAAIiAAkJzhI3GQDVAQAiAAkJzhI3GQDVAQAAAA==.Saintjeb:BAACLgAFFH8FAAIbAAIJ5AzEDAB0AAAbAAIJ5AzEDAB0AAAuAAQKfxQAAhsACAkDEtgXAFgBABsACAkDEtgXAFgBAAEuAAUUAwkEAAcAAAAA.Saitami:BAAALgAECgEJAQAAAA==.Saitamå:BAAALgAECgYJDAAAAA==.Sakisan:BAAALgAECgEJAgAAAA==.Salinity:BAABLgAECn8nAAMTAAkJmCIeBgAbAwATAAkJXCIeBgAbAwAmAAcJRSBvBwBRAgAAAA==.Samanaras:BAABLgAECn8VAAIgAAgJHBB8GABsAQAgAAgJHBB8GABsAQAAAA==.Sanari:BAAALgADCgMJAwAAAA==.Sangwyn:BAAALgAECgUJBQABLgAECgcJIAApALAjAA==.Santiago:BAAALgAECgYJDwAAAA==.Saratoga:BAABLgAECn8WAAIZAAcJexoJXgDJAQAZAAcJexoJXgDJAQAAAA==.Sarkana:BAABLgAECn8kAAIhAAkJfB77BwDnAgAhAAkJfB77BwDnAgAAAA==.Sarticor:BAAALgAECgEJAQAAAA==.Sassquatch:BAACLgAFFH8FAAIYAAIJVQ6joQCWAAAYAAIJVQ6joQCWAAAuAAQKfyQAAxgABwlLGthLALwBABgABwlLGthLALwBAAkAAQkgBZtSACMAAAAA.Saxonn:BAABLgAECn8oAAMeAAgJ+w2kMQBJAQAeAAgJ+w2kMQBJAQAcAAMJaQM5iABzAAAAAA==.Saydis:BAAALgAECgYJEAAAAA==.',
Sc='Schuftt:BAABLgAECn8UAAMaAAgJExrAAwCyAQAaAAgJExrAAwCyAQAfAAEJ9BQODgBGAAAAAA==.',
Se='Seafoodtower:BAAALgAECgEJAQAAAA==.Sebattan:BAAALgAECgYJDwAAAA==.Seleine:BAAALgADCgEJAQABLgAECgkJPAABALgZAA==.Sello:BAAALgAECgEJAgAAAA==.Seltzers:BAAALgADCgQJCgAAAA==.Selunella:BAAALgADCgEJAQABLgAECgUJDwAHAAAAAA==.Selvester:BAABLgAECn8hAAIIAAcJZyXSCQB6AgAIAAcJZyXSCQB6AgAAAA==.Senadria:BAABLgAECn8XAAIEAAUJ9AkOowDOAAAEAAUJ9AkOowDOAAAAAA==.Senseishifu:BAACLgAFFH8IAAIIAAQJBgzFJAD7AAAIAAQJBgzFJAD7AAAuAAQKfyEAAggACQk7F2sUAO0BAAgACQk7F2sUAO0BAAAA.Seorsen:BAAALgADCgcJEAAAAA==.Servinghunt:BAAALgAECgYJCwAAAA==.Sevalandre:BAAALgADCgYJBgABLgAECggJIgAYAFkYAA==.',
Sh='Shamatrest:BAAALgAECgEJAwABLgAECgkJKAAYAN4kAA==.Shamina:BAACLgAFFH8MAAICAAUJswjmBgAWAQACAAUJswjmBgAWAQAuAAQKfx0AAgIACAmHGRIIABQCAAIACAmHGRIIABQCAAAA.Shamite:BAAALgAECgMJAwABLgAECggJDwAHAAAAAA==.Shammalin:BAABLgAECn8iAAMeAAgJ1As1NwArAQAeAAgJ1As1NwArAQAcAAUJlgxdbQDZAAAAAA==.Shamminator:BAAALgADCgMJAwAAAA==.Shamorex:BAABLgAECn8rAAIeAAgJRBY0IwCfAQAeAAgJRBY0IwCfAQAAAA==.Shanoth:BAAALgAECgYJBgABLgAECggJIgAYAFkYAA==.Sharkbones:BAAALgAECgEJAQAAAA==.Shatter:BAAALgAECgcJDwAAAA==.Shax:BAAALgAECgUJBgABLgAECgkJJwATAJgiAA==.Shiftyy:BAAALgAECgcJCgAAAA==.Shogun:BAAALgADCgQJCAAAAA==.Shoopywoopy:BAAALgAECgEJAQAAAA==.Shteph:BAAALgAECgYJBgAAAA==.Shîftfaced:BAAALgAECgIJAgAAAA==.',
Si='Siaerosia:BAAALgADCgEJAQAAAA==.',
Sk='Skaarr:BAABLgAECn8VAAIKAAgJ3wggQQAXAQAKAAgJ3wggQQAXAQAAAA==.',
Sl='Slayn:BAABLgAECn8dAAIBAAYJ4BKXlwAvAQABAAYJ4BKXlwAvAQAAAA==.Sleinx:BAAALgADCgMJAwABLgAFFAUJEgAeAEEaAA==.Slowhealsboi:BAAALgAECgQJBAAAAA==.Slushpuppie:BAAALgADCgYJBgAAAA==.Slyrak:BAABLgAECn8tAAMRAAgJHBkRBQD0AQARAAgJHBkRBQD0AQALAAMJoQiWLABcAAAAAA==.Slyva:BAAALgAECgMJAwAAAA==.',
Sm='Smithbruh:BAEALgAECgQJBAABLgAECggJIQAIAMwhAA==.Smitus:BAAALgAECggJDQAAAA==.Smokescale:BAAALgADCgcJCAAAAA==.',
Sn='Snackie:BAABLgAECn8kAAIcAAgJih6xDgC0AgAcAAgJih6xDgC0AgAAAA==.Sneakyjewel:BAAALgADCgkJEAAAAA==.Snotpig:BAAALgAECggJBwAAAA==.',
So='Solarious:BAAALgAECgEJAQAAAA==.Sorscrasus:BAAALgADCgUJCAAAAA==.Soulcolektor:BAAALgADCgcJDwAAAA==.Souled:BAAALgAECgQJBQAAAA==.',
Sp='Sparroh:BAAALgADCgEJAQAAAA==.Spikedriver:BAABLgAECn8kAAIGAAkJJxA7QgCvAQAGAAkJJxA7QgCvAQAAAA==.Spradwurd:BAAALgAECgUJCAAAAA==.',
Sq='Squee:BAABLgAECn8UAAMFAAgJuBU2KABJAQAFAAgJuBU2KABJAQAIAAEJ1wF4mQAaAAABLgAECggJFAAFALgVAA==.',
St='Stantonio:BAAALgAECggJEgAAAA==.Stariane:BAABLgAECn8jAAINAAkJeh0YCQBsAgANAAkJeh0YCQBsAgAAAA==.Startaster:BAAALgAFFAEJAQAAAA==.Starvoid:BAAALgAECgEJAQAAAA==.Steaktartare:BAABLgAECn8fAAIhAAcJdw2gOABAAQAhAAcJdw2gOABAAQAAAA==.Steeldk:BAAALgAECgQJBAAAAA==.Steelfist:BAAALgAECgYJCgAAAA==.Steelpunch:BAAALgAECgUJCAAAAA==.Steelwill:BAAALgAECgIJAgAAAA==.Stonii:BAAALgADCgUJBQAAAA==.Stony:BAABLgAECn8sAAIGAAgJ3yFmFgB4AgAGAAgJ3yFmFgB4AgAAAA==.Stonyy:BAAALgAECgYJCwAAAA==.Stratpanda:BAAALgADCgkJCQAAAA==.Strelizia:BAAALgAECgIJAgAAAA==.Stressful:BAAALgADCgQJBAAAAA==.',
Su='Sub:BAAALgAECgMJAwABLgAFFAUJGwACALMjAA==.Suetekh:BAAALgADCgUJBQAAAA==.Sukidaiyo:BAABLgAECn8VAAIoAAgJQhZbCADCAQAoAAgJQhZbCADCAQAAAA==.Summers:BAAALgAECgUJDAAAAA==.Sumonmyface:BAAALgAECgQJCgABLgAECgkJJgAUAMEQAA==.Sunshield:BAAALgAECgMJAwAAAA==.Superillbomb:BAAALgADCgcJCwAAAA==.Superold:BAAALgAECggJCAAAAA==.Suraug:BAAALgADCgcJBwAAAA==.Suzakku:BAAALgAECgQJBQAAAA==.',
Sw='Swampraught:BAABLgAECn8jAAMTAAcJiBdPUACTAQATAAcJiBdPUACTAQAmAAEJtA2ocAA1AAAAAA==.',
Sy='Syd:BAAALgADCgYJBgAAAA==.Syletage:BAAALgAECgMJBQAAAA==.Synd:BAAALgADCgEJAQAAAA==.Synrae:BAAALgAECggJBwAAAA==.Syral:BAAALgAECgQJCQAAAA==.Syrion:BAAALgAECgQJBAAAAA==.Sythrane:BAAALgAECgUJBQAAAA==.',
Ta='Taarii:BAAALgADCggJCAAAAA==.Talisoudwave:BAAALgAECgYJDQABLgAECggJIAAPABElAA==.Talomeo:BAAALgAECgIJAgAAAA==.Taradan:BAAALgAECgEJAQAAAA==.Taraxus:BAAALgADCgUJBQAAAA==.Tateraider:BAABLgAECn80AAMjAAkJvx0pBgCKAgAjAAkJvx0pBgCKAgAKAAEJQwv5iwAxAAAAAA==.Taurnator:BAAALgAECgMJBAAAAA==.Taylorswift:BAAALgAECgMJBgAAAA==.Tayven:BAAALgADCgEJAQAAAA==.',
Te='Tednougat:BAAALgADCgYJBgAAAA==.Telain:BAABLgAECn8+AAQhAAgJiRmfFgAuAgAhAAgJiRmfFgAuAgAZAAUJ8xKOkwArAQAbAAIJhxZGMAB3AAAAAA==.Tensuki:BAAALgAECgMJAwAAAA==.Teslah:BAAALgADCgQJBAAAAA==.',
Th='Thakilla:BAACLgAFFH8GAAIiAAIJMgQ1NABvAAAiAAIJMgQ1NABvAAAuAAQKfzEAAiIACAkuFLgdAK0BACIACAkuFLgdAK0BAAAA.Thanosonmage:BAAALgADCgcJBwAAAA==.Thavik:BAAALgADCgEJAwAAAA==.Theolodin:BAAALgAECgQJDwAAAA==.Thordrik:BAAALgAECgUJCQAAAA==.Thorix:BAABLgAECn8UAAINAAcJpREmHQBWAQANAAcJpREmHQBWAQAAAA==.Thotmir:BAAALgAECgMJAwAAAA==.Thícc:BAAALgADCgkJCgAAAA==.',
Ti='Tigerburn:BAAALgADCgkJCQAAAA==.Tikibiki:BAAALgADCgMJAwAAAA==.Timbereses:BAAALgADCgUJBQAAAA==.Timberreaper:BAAALgAECgMJBAAAAA==.Tinyz:BAABLgAECn8aAAMpAAYJmBaLJQB1AQApAAYJmBaLJQB1AQADAAUJTwbSTgCiAAAAAA==.',
To='Tolua:BAAALgAECgUJCAAAAA==.Tonata:BAABLgAECn8aAAMQAAkJBQuQOQAeAQAQAAkJBQuQOQAeAQALAAgJlQ03GgAQAQAAAA==.Tonythetiger:BAAALgAECgEJAQABLgAECgkJMAAJABcfAA==.Tootsie:BAAALgADCgYJEAAAAA==.Tormentus:BAAALgAECgMJAwAAAA==.',
Tr='Trenton:BAAALgADCgUJBwAAAA==.Trexlot:BAAALgAECgIJBQAAAA==.Trinjal:BAABLgAECn8uAAMOAAkJFRu/DgB/AgAOAAkJFRu/DgB/AgAFAAQJgxsEOAD1AAAAAA==.Trishift:BAAALgAECgQJBgAAAA==.Trueshru:BAAALgAECgIJAwAAAA==.',
Tu='Tubular:BAAALgAECgMJBQAAAA==.Tuskadin:BAACLgAFFH8JAAIZAAQJLRuVJQBFAQAZAAQJLRuVJQBFAQAuAAQKfyoAAhkACAlFJK4bAMQCABkACAlFJK4bAMQCAAAA.',
Tw='Tweeq:BAAALgAECgQJBQAAAA==.',
Ty='Tyjan:BAAALgAECgYJEwAAAA==.Tyrana:BAAALgAECgMJAwAAAA==.Tyriq:BAAALgADCgYJBgAAAA==.',
['Tã']='Tãz:BAAALgAECgEJAgAAAA==.',
Ul='Ulra:BAAALgADCgkJCgAAAA==.',
Un='Unclothed:BAABLgAECn8cAAIkAAcJlwu6GAARAQAkAAcJlwu6GAARAQAAAA==.Unicorn:BAAALgADCggJCgAAAA==.Untòld:BAAALgADCggJCAABLgAECgcJGQABABQPAA==.',
Va='Valentine:BAAALgADCgIJAgAAAA==.Valitymage:BAAALgADCgEJAQAAAA==.Varthios:BAAALgAECgEJAgAAAA==.Varyusha:BAAALgAECgMJBAAAAA==.',
Ve='Velene:BAAALgADCgEJAQABLgAECgkJPAABALgZAA==.Venzallow:BAAALgAECgUJBwAAAA==.Veralynn:BAAALgADCgcJBwAAAA==.Veravibes:BAAALgAECgQJCwAAAA==.Vermagnus:BAABLgAECn8cAAIIAAgJgRq8EwDzAQAIAAgJgRq8EwDzAQAAAA==.Vespor:BAABLgAECn8ZAAIPAAYJHR+/IwAKAgAPAAYJHR+/IwAKAgAAAA==.',
Vi='Viktorya:BAABLgAECn8eAAILAAcJGBedFgDlAQALAAcJGBedFgDlAQAAAA==.Vilelyn:BAABLgAECn8iAAMFAAgJ+hS1FwDMAQAFAAgJ+hS1FwDMAQAOAAIJURIzbQBrAAABLgAECgcJKgAZAC0cAA==.Viloria:BAABLgAECn8mAAIdAAcJvRIDGgA8AQAdAAcJvRIDGgA8AQAAAA==.Vincent:BAAALgAECgMJBgAAAA==.Virrard:BAABLgAECn8qAAMGAAgJxRwCLAADAgAGAAgJxRwCLAADAgAVAAIJYA+gdQBoAAAAAA==.Vitalyellow:BAAALgADCgYJBgAAAA==.',
Vl='Vladimor:BAABLgAECn8WAAITAAcJZxnUZABeAQATAAcJZxnUZABeAQAAAA==.Vladimyrr:BAABLgAECn8XAAIZAAgJ1hW4bwBvAQAZAAgJ1hW4bwBvAQAAAA==.',
Vo='Vodan:BAAALgADCgEJAQAAAA==.Voidplague:BAAALgAECgYJDQAAAA==.Voidscarred:BAAALgAECgQJEgAAAA==.Vozrezz:BAABLgAECn8fAAMFAAcJch23HQCXAQAFAAcJSxq3HQCXAQAIAAYJUhqNIwBvAQAAAA==.',
Vu='Vualake:BAAALgADCgcJDQAAAA==.',
Vy='Vyridian:BAAALgAECgQJAwABLgAECgYJEwAHAAAAAA==.',
['Vë']='Vëda:BAABLgAECn8kAAIpAAkJKxFHGgDPAQApAAkJKxFHGgDPAQAAAA==.',
Wa='Wardragon:BAAALgADCgcJCwAAAA==.Warrwras:BAAALgADCgcJDgAAAA==.Wasical:BAAALgAECgQJBAAAAA==.',
Wh='Wheaties:BAAALgAECgcJDAABLgAECgkJMAAJABcfAA==.',
Wi='Wicker:BAABLgAECn8vAAIdAAkJ/SEmAwDVAgAdAAkJ/SEmAwDVAgAAAA==.Wickievoker:BAAALgADCgkJCQABLgAECgkJLwAdAP0hAA==.Wintin:BAAALgAECgEJAgAAAA==.Wiskey:BAAALgAECgYJCQAAAA==.Wiçker:BAAALgAECgYJBgABLgAECgkJLwAdAP0hAA==.',
Wo='Wolford:BAABLgAECn8aAAIPAAcJKhtYJgD6AQAPAAcJKhtYJgD6AQAAAA==.Woogie:BAAALgADCgYJCgAAAA==.Wordz:BAAALgAECgEJAgAAAA==.',
Wr='Wras:BAABLgAECn8hAAIJAAcJrB3ODgDsAQAJAAcJrB3ODgDsAQAAAA==.Wretched:BAAALgAECgcJBQAAAA==.',
Wy='Wyrnn:BAAALgADCgcJEAAAAA==.Wysstical:BAAALgAECgcJBwABLgAFFAUJGwACALMjAA==.',
['Wò']='Wòbbles:BAAALgAECgYJEQABLgAECgYJFgABABMPAA==.',
Xa='Xalnova:BAAALgADCgYJDAAAAA==.Xandos:BAAALgAECgIJAgAAAA==.Xandrah:BAABLgAECn8ZAAIDAAYJ8gc5QQDgAAADAAYJ8gc5QQDgAAAAAA==.Xanslash:BAABLgAECn8jAAIEAAkJwR2CGABmAgAEAAkJwR2CGABmAgAAAA==.Xari:BAACLgAFFH8bAAIBAAYJ7xrgGwC1AQABAAYJ7xrgGwC1AQAuAAQKfywAAgEACQl1IwcSADsDAAEACQl1IwcSADsDAAAA.',
Xh='Xhalo:BAAALgADCggJCAAAAA==.',
Xi='Xiansai:BAABLgAECn8fAAIDAAkJbxaPFwDnAQADAAkJbxaPFwDnAQAAAA==.Xiongwei:BAAALgAECgEJAgAAAA==.',
Ya='Yappey:BAACLgAFFH8GAAIIAAIJxx0zNQCtAAAIAAIJxx0zNQCtAAAuAAQKfx8AAggACAkXIokHAJ8CAAgACAkXIokHAJ8CAAAA.',
Ye='Yehni:BAACLgAFFH8FAAIpAAMJKSO/DgAtAQApAAMJKSO/DgAtAQAuAAQKf0AAAikACQmtJO8BAHgDACkACQmtJO8BAHgDAAAA.',
Yo='Youthinasia:BAAALgAECgQJBAAAAA==.',
Ys='Ys:BAAALgAECgIJAgABLgAECgkJJAApACsRAA==.',
Yu='Yurasick:BAAALgAECgIJAgAAAA==.',
Za='Zaesha:BAAALgADCgYJCQAAAA==.Zalarii:BAAALgADCgEJAgAAAA==.Zarox:BAABLgAECn8eAAIYAAkJJBKzSQDCAQAYAAkJJBKzSQDCAQAAAA==.',
Ze='Zeroelement:BAABLgAECn8WAAIhAAgJPB9MLQCDAQAhAAgJPB9MLQCDAQAAAA==.',
Zi='Zimgir:BAAALgADCgEJAQAAAA==.',
Zo='Zombiehippo:BAABLgAECn8sAAIBAAkJTBv4JABsAgABAAkJTBv4JABsAgAAAA==.Zorcons:BAAALgAECgEJAQAAAA==.',
Zu='Zuuzuu:BAAALgADCgEJAQAAAA==.',
['Áu']='Áutarch:BAABLgAECn8WAAIKAAcJEgrPRAAJAQAKAAcJEgrPRAAJAQAAAA==.',
['Èl']='Èlty:BAAALgAECgMJAwAAAA==.',
['Ðe']='Ðemøn:BAAALgAECgUJDQAAAA==.',
['Ðr']='Ðrexy:BAAALgADCgUJBQAAAA==.',
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
