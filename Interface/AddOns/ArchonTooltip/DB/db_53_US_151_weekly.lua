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

local lookup = {'Monk-Mistweaver','Hunter-BeastMastery','DeathKnight-Blood','Shaman-Restoration','Druid-Feral','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','DeathKnight-Frost','Warlock-Demonology','DemonHunter-Devourer','Warlock-Destruction','Warlock-Affliction','Druid-Restoration','Druid-Balance','Warrior-Fury','Evoker-Devastation','Evoker-Preservation','DeathKnight-Unholy','Shaman-Elemental','Shaman-Enhancement','Hunter-Marksmanship','Unknown-Unknown','Paladin-Retribution','Rogue-Subtlety','Rogue-Assassination','Warrior-Arms','Mage-Arcane','DemonHunter-Havoc','Mage-Frost','Warrior-Protection','Monk-Windwalker','DemonHunter-Vengeance','Paladin-Protection','Evoker-Augmentation','Monk-Brewmaster','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Malfurion',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aaluah:BAAANQAECgQICgAAAA==.',
Ab='Abc:BAAANQAECgUIBQABNQAECgkJKwABAGoSAA==.',
Ac='Aceknight:BAAANQADCgQIBAAAAA==.Aclord:BAAANQADCgEIAQAAAA==.Acmis:BAAANQAECgIIAwABNQAECgYIGgACAOMfAA==.Acp:BAABNQAECn8aAAICAAgKAB69UwBzAgACAAgKAB69UwBzAgAAAA==.',
Ad='Adomangma:BAAANQABCgQIBQAAAA==.',
Ae='Aetherconri:BAAANQADCgYICQAAAA==.',
Ah='Ahjumma:BAABNQAECn8yAAIDAAkK0h+MDgA5AwADAAkK0h+MDgA5AwAAAA==.',
Ai='Ailharn:BAABNQAECn8iAAIEAAgKsRfWTQApAgAEAAgKsRfWTQApAgAAAA==.',
Ak='Akadein:BAAANQAECgQIBQAAAA==.Akun:BAAANQADCgYIDAABNQAECgcIGQAFAPciAA==.Akurantirea:BAABNQAECn8ZAAIFAAcK9yIHCQC5AgAFAAcK9yIHCQC5AgAAAA==.',
Al='Aldin:BAAANQAECgYICAAAAA==.Alecto:BAAANQABCgYIBgAAAA==.Algerax:BAAANQAECgIIBQAAAA==.Allise:BAAANQAECgUICwAAAA==.Alphamaled:BAABNQAECn8iAAIDAAkKdQfGaABNAQADAAkKdQfGaABNAQAAAA==.Alva:BAAANQADCgYICAAAAA==.Aléthia:BAABNQAECn8ZAAIGAAgKgge+iQB1AQAGAAgKgge+iQB1AQAAAA==.',
Am='Ambaxius:BAAANQADCggIIgAAAA==.',
An='Anathemá:BAAANQAECgUIBgAAAA==.Ang:BAAANQAECgYIBgAAAA==.Ange:BAAANQADCggIEAAAAA==.Angeon:BAAANQAECgQIBQAAAA==.',
Ap='Apawpriest:BAABNQAECn8oAAIHAAgKMxPeIgAZAgAHAAgKMxPeIgAZAgAAAA==.',
Ar='Archious:BAAANQADCgQIBAAAAA==.Ardeyn:BAAANQADCgYICAAAAA==.Arke:BAABNQAECn8cAAQHAAgKThQNIwAXAgAHAAgKThQNIwAXAgAGAAMKtgSC4gB3AAAIAAEKQAaCLgAnAAAAAA==.Arkies:BAAANQADCgcIBwABNQAECggIHAAHAE4UAA==.Arlynn:BAAANQADCggICAABNQAECggIHwAJAFUYAA==.Arraeroda:BAABNQAECn8aAAIKAAYKHxaLTQB5AQAKAAYKHxaLTQB5AQAAAA==.Arrence:BAAANQAECgQIBQABNQAECgkJMgADANIfAA==.Artleandra:BAAANQADCgMIAwABNQAECgkJHgALAHsWAA==.',
As='Ashara:BAAANQAECgEIAQAAAA==.Ashlena:BAAANQADCgQIBAABNQAECggIGwAMAAQWAA==.Astela:BAABNQAECn8eAAMNAAgKNxT7CgBHAgANAAgKTRP7CgBHAgAOAAMKrQujGQC3AAAAAA==.Asuka:BAAANQAECgEIAQAAAA==.',
Au='Aumtatsat:BAAANQAECgUICQABNQAECgkJHgAHALkiAA==.Autumn:BAABNQAECn8oAAMPAAgKCR8oEwCxAgAPAAgKCR8oEwCxAgAQAAYKQwoGaQAjAQAAAA==.',
Av='Avan:BAAANQADCggICAAAAA==.Avatan:BAABNQAECn8fAAIRAAgKzwswEACiAQARAAgKzwswEACiAQAAAA==.Avedeath:BAAANQADCggIHQAAAA==.Aveena:BAAANQADCgMIAwAAAA==.Averlis:BAAANQADCgIIAgAAAA==.',
Ay='Ayane:BAAANQABCgYICAAAAA==.Ayara:BAACNQAFFH8aAAIMAAYKghyZAgBEAgAMAAYKghyZAgBEAgA1AAQKf1QAAgwACQpFJRcEAJMDAAwACQpFJRcEAJMDAAAA.Ayrad:BAAANQAECgMIAwAAAA==.',
Az='Aziel:BAAANQADCgMIAwAAAA==.',
Ba='Badderdragon:BAACNQAFFH8FAAISAAIKYwf5DAB7AAASAAIKYwf5DAB7AAA1AAQKfyoAAxIACQqEF44NAIYCABIACQqEF44NAIYCABMAAQpMBmNMADoAAAAA.Badfish:BAAANQAECgEIAQAAAA==.Badmrmittens:BAAANQAECgMIAwAAAA==.Badmuffin:BAABNQAECn8aAAICAAYKIhT+pwCxAQACAAYKIhT+pwCxAQAAAA==.Bahkita:BAAANQAECgQIBAAAAA==.Bakatran:BAAANQADCgMIBAAAAA==.Balamuth:BAAANQADCgYIBgAAAA==.Bandrui:BAAANQADCgYICgAAAA==.Barthas:BAAANQABCgQIBAAAAA==.',
Be='Bearlygrillz:BAAANQAECgQIBQAAAA==.Begachan:BAAANQADCgYIBgAAAA==.Berkstein:BAAANQAECgUIDwAAAA==.',
Bi='Bigbadrock:BAAANQAECgUIBQAAAA==.Bigcai:BAAANQADCgYIBgAAAA==.Biggisnicker:BAAANQAECgYIDgAAAA==.Bigspriesty:BAAANQAECgUICgAAAA==.Bigtone:BAAANQAECgUICwAAAA==.Bimbomz:BAABNQAECn8hAAIUAAgKiCGfJQCmAgAUAAgKiCGfJQCmAgAAAA==.Biochemist:BAAANQADCgMIBAABNQAECgkJLAAEACweAA==.Bioengineer:BAAANQADCgYIBgABNQAECgkJLAAEACweAA==.Biogenic:BAABNQAECn8sAAQEAAkKLB5qMgCUAgAEAAgK8R1qMgCUAgAVAAcKhBQwYwD0AQAWAAEKIAXgNQA1AAAAAA==.Biomass:BAAANQADCgcICAABNQAECgkJLAAEACweAA==.Biophysics:BAAANQAECgUIDQABNQAECgkJLAAEACweAA==.Birdbrain:BAACNQAFFH8FAAIXAAIKVhbVGgCWAAAXAAIKVhbVGgCWAAA1AAQKfyIAAhcACQpzIRcNAAkDABcACQpzIRcNAAkDAAAA.',
Bl='Bleebloop:BAAANQAECgUICgABNQAECgkJMQAWAI8kAA==.Blewîsa:BAAANQADCgcJCgAAAA==.Blvck:BAAANQADCgcIDQAAAA==.',
Bo='Boodylicious:BAAANQAECgEIAQABNQAECgcIHAAGANIMAA==.Borucmonk:BAAANQADCgcIFgABNQAECggIIwARAHoTAA==.Borucwar:BAABNQAECn8jAAIRAAgKehNQDAD1AQARAAgKehNQDAD1AQAAAA==.',
Br='Braedia:BAAANQAECgUIBwAAAA==.Brassticus:BAAANQADCgcIBwAAAA==.Brawrski:BAAANQAECgMIAwABNQAECgUIEQAYAAAAAA==.Briele:BAABNQAECn8dAAIJAAcKWg9mhACKAQAJAAcKWg9mhACKAQAAAA==.Brise:BAAANQAECgEIAQAAAA==.Brosabi:BAAANQAECgYIDwABNQAECggIHAALANMjAA==.Brucewaynexb:BAAANQABCgYIBgAAAA==.',
Bu='Bubs:BAAANQAECgQIDwAAAA==.Buddhïst:BAACNQAFFH8KAAICAAQKziAcDgBtAQACAAQKziAcDgBtAQA1AAQKfyAAAwIACQphJEYUAEwDAAIACQphJEYUAEwDABcAAQp5E3Z/AEEAAAAA.Burrhas:BAAANQADCggICgAAAA==.Buxky:BAAANQADCgIJAgAAAA==.',
['Bí']='Bítten:BAAANQAECgUICQAAAA==.',
Ca='Cakesinatra:BAAANQADCggIDQABNQAECgkJHgALAHsWAA==.Cakewastaken:BAABNQAECn8eAAQLAAkKexZkSgBxAgALAAkKexZkSgBxAgAOAAIKAAABHwB+AAANAAEKEhCldAA5AAAAAA==.Cakke:BAAANQAECgIIAgAAAA==.Calkestis:BAAANQADCgUJDAAAAA==.Candre:BAABNQAECn8yAAIZAAkK6CJ+EgB8AwAZAAkK6CJ+EgB8AwAAAA==.Candyears:BAAANQADCgIIAgAAAA==.Capii:BAAANQAECgMIBAABNQAECgUICwAYAAAAAA==.Capristal:BAAANQAECgUICwAAAA==.Carebeär:BAAANQADCgQIBAAAAA==.Caròl:BAAANQADCgYIDAAAAA==.Cassiera:BAABNQAECn8yAAIJAAkKFBrOLQCtAgAJAAkKFBrOLQCtAgAAAA==.Cauldren:BAAANQADCggILgAAAA==.',
Ch='Chalice:BAAANQADCgYICwAAAA==.Charkycc:BAAANQADCgMIAwAAAA==.Charmed:BAAANQADCgQIBAABNQAECgUICwAYAAAAAA==.Chay:BAABNQAECn8lAAILAAkKBBzXMQC+AgALAAkKBBzXMQC+AgAAAA==.Chaylin:BAAANQAECgEIAQABNQAECgkJJQALAAQcAA==.Chikage:BAAANQAECgEIAQAAAA==.Chillen:BAABNQAECn8eAAMaAAgKRh3HDACmAgAaAAgKRh3HDACmAgAbAAEK8w87mQBCAAAAAA==.Chillzen:BAAANQADCgUIBQAAAA==.Chinofwin:BAAANQABCgIIAgAAAA==.Chivo:BAAANQAECgUIDQAAAA==.Chopu:BAABNQAECn8eAAIRAAcKPh0YCgAqAgARAAcKPh0YCgAqAgAAAA==.Chuckspadina:BAABNQAECn8yAAIJAAkK3xo4IgDiAgAJAAkK3xo4IgDiAgAAAA==.Chuggin:BAAANQADCgMIAwAAAA==.Chyna:BAAANQAECgcIDgAAAA==.',
Ci='Cibø:BAAANQAECgUIEQAAAA==.Cilghalcao:BAAANQAECggIEgAAAA==.Cirdae:BAABNQAECn8vAAMEAAkKERVfSgA2AgAEAAkKERVfSgA2AgAVAAIKTxH/BQF5AAAAAA==.',
Cl='Cleric:BAAANQAECgEIAQABNQAECgkJJAALADUbAA==.Cloudstone:BAAANQAECgYIDgAAAA==.Clownfish:BAAANQADCgQIBAAAAA==.Clõud:BAABNQAECn8eAAIRAAcKRROhDwCtAQARAAcKRROhDwCtAQAAAA==.',
Co='Cococolalaw:BAAANQADCgEIAQAAAA==.Coggknocker:BAAANQABCgMIAwAAAA==.Coldsnaps:BAAANQADCgYIBgAAAA==.Conc:BAABNQAECn8rAAIcAAkK+iHRFwBYAwAcAAkK+iHRFwBYAwAAAA==.Cormac:BAAANQADCggICAAAAA==.',
Cp='Cpthardfap:BAAANQAECgUICgAAAA==.',
Cr='Cragshot:BAAANQAECgcICgAAAA==.Crazynip:BAABNQAECn81AAIJAAkKvyFzCQB8AwAJAAkKvyFzCQB8AwAAAA==.Crickit:BAAANQAECgYIEwAAAA==.Crikit:BAAANQAECgQIBAABNQAECgYIEwAYAAAAAA==.Crispr:BAAANQADCggIDAAAAA==.Cryavus:BAAANQADCggIDwABNQAECgkJMAAGAAggAA==.Crylucis:BAABNQAECn8wAAIGAAkKCCAWGwAFAwAGAAkKCCAWGwAFAwAAAA==.Crymagus:BAAANQAECgUIBQABNQAECgkJMAAGAAggAA==.Crypticál:BAAANQADCgMIAwABNQADCgcIDgAYAAAAAA==.',
Cu='Cujo:BAABNQAECn8vAAIVAAkKUh24IwD1AgAVAAkKUh24IwD1AgAAAA==.',
Cy='Cyanidesun:BAAANQAECgEIAQAAAA==.Cybre:BAAANQAECgUICwAAAA==.Cyndaquill:BAAANQAECggIAgAAAA==.Cyndil:BAABNQAECn8gAAMNAAcKgRKiEwDSAQANAAcKgRKiEwDSAQALAAEK+QIZRwEsAAAAAA==.Cysora:BAAANQAECgEJAQAAAA==.Cysport:BAAANQAECgIIBAAAAA==.',
['Cä']='Cästiel:BAAANQAECgQIDAAAAA==.',
Da='Daahntaat:BAAANQABCgMJBQAAAA==.Daesyn:BAAANQABCgMIBAAAAA==.Dakkaglyndur:BAAANQAECgIIAQAAAA==.Dallei:BAAANQAECgYIDQAAAA==.Danbearpig:BAAANQABCgQIBAAAAA==.Dandish:BAABNQAECn8kAAILAAgKnBHafQDnAQALAAgKnBHafQDnAQAAAA==.Darcaine:BAAANQADCgUIBQABNQAECgkJKwANACAQAA==.Darcane:BAABNQAECn8rAAQNAAkKIBDOEQDnAQANAAgKVhDOEQDnAQALAAcKGQkmugBUAQAOAAIKGgluHwB5AAAAAA==.Darctanian:BAAANQAECgIIBAAAAA==.Darkchaos:BAAANQADCggICAAAAA==.Darkdestîny:BAAANQADCgcIBwAAAA==.Darkvayne:BAABNQAECn8eAAICAAcKpiJcPwCqAgACAAcKpiJcPwCqAgAAAA==.Darrington:BAAANQAECgUIDgAAAA==.Dathrel:BAAANQADCggIMwAAAA==.Davoodoomon:BAAANQAECgQIBQAAAA==.Dawnfather:BAAANQABCgYIBwAAAA==.Dawnfoxer:BAAANQAECgQIEAAAAA==.',
De='Deathpig:BAAANQADCggIAgAAAA==.Deburr:BAAANQADCgEIAQABNQADCgQIBAAYAAAAAA==.Deezaster:BAAANQAECgEIAQABNQAECggIDgAYAAAAAA==.Def:BAABNQAECn8gAAIdAAgKARglggB5AgAdAAgKARglggB5AgAAAA==.Dejected:BAAANQAECgcIBwAAAA==.Delani:BAABNQAECn8XAAICAAcKzxdCggAEAgACAAcKzxdCggAEAgAAAA==.Delisius:BAAANQADCgYIBgAAAA==.Deltaco:BAAANQAECgEIAgAAAA==.Dementis:BAAANQADCggIEQAAAA==.Demonnova:BAACNQAFFH8OAAMMAAYKmRKkBwCLAQAMAAUKURekBwCLAQAeAAEKbwQwIAAwAAA1AAQKfyMAAwwACQplHCAgAEoCAAwACAotHSAgAEoCAB4AAgrNDaJ+AHUAAAAA.Dendude:BAAANQABCgEIAQAAAA==.Dessertname:BAAANQAECgMIAQABNQAFFAQIDgAfAGUPAA==.Destiny:BAAANQAECgIJAgAAAA==.Detrimentum:BAAANQAECgMIAwABNQAECgkJHgALAHsWAA==.Devinity:BAAANQADCgUIBQAAAA==.Dezsp:BAACNQAFFH8dAAIHAAcKBCFSAQCuAgAHAAcKBCFSAQCuAgA1AAQKfzAAAgcACQqEJswCAK4DAAcACQqEJswCAK4DAAAA.',
Dg='Dghunter:BAABNQAECn8aAAICAAcK8QJ4EQHaAAACAAcK8QJ4EQHaAAAAAA==.',
Di='Diabolis:BAAANQAECgUICgAAAA==.Dietrinea:BAAANQADCgIIAgAAAA==.Diyoka:BAAANQADCgQIBAAAAA==.',
Do='Docsored:BAAANQAECgUIDwAAAA==.Dontholdback:BAAANQADCgUIBQAAAA==.Donuts:BAAANQAECgYIEAAAAA==.Doomchick:BAAANQABCggIDgAAAA==.',
Dr='Dragn:BAAANQAECgIIAwAAAA==.Dragnas:BAABNQAECn8yAAIcAAkKzBp9RwCwAgAcAAkKzBp9RwCwAgAAAA==.Dragniperake:BAABNQAECn8bAAIJAAgKPhhjSwA5AgAJAAgKPhhjSwA5AgAAAA==.Dragnspawn:BAAANQADCggIDQAAAA==.Drbluejeans:BAAANQAECgEIAQABNQAECggIDQAYAAAAAA==.Drbug:BAAANQAECgYIDAABNQAECggIDQAYAAAAAA==.Drdots:BAABNQAECn8mAAILAAkK4hf9RgB7AgALAAkK4hf9RgB7AgAAAA==.Dreadnaunt:BAAANQAECgQICAAAAA==.Dreamhc:BAABNQAECn8gAAMdAAgKIx1PwgD+AQAdAAYKOB9PwgD+AQAfAAMKrxikJQDAAAAAAA==.Dreamwave:BAAANQADCggIEAABNQADCggIEQAYAAAAAA==.Dresperea:BAAANQADCgUIBQAAAA==.Drewed:BAAANQAECgYIDQAAAA==.Drmage:BAAANQAECgEIAQAAAA==.Drugral:BAACNQAFFH8FAAIUAAIKkwt+GQCMAAAUAAIKkwt+GQCMAAA1AAQKfywAAhQACQoQI/saAOkCABQACQoQI/saAOkCAAAA.',
Du='Dugronn:BAAANQAECgYICQAAAA==.',
Dw='Dwarfvadar:BAAANQAECgcICgAAAA==.',
Ea='Eadric:BAAANQAECgUICQAAAA==.',
Ec='Echiza:BAAANQAECgQIBgAAAA==.Ecricketz:BAAANQAECgQIBwAAAA==.',
Ed='Edda:BAAANQAECgEJAQABNQAECggIIAAdAAEYAA==.',
El='Elanthemage:BAAANQAECgUIDwAAAA==.Elarya:BAAANQADCggICgAAAA==.Electria:BAAANQADCgIIAgAAAA==.Eleison:BAACNQAFFH8ZAAIHAAYK/x7OAgBQAgAHAAYK/x7OAgBQAgA1AAQKfyEAAwcACQotIvAIAEwDAAcACQotIvAIAEwDAAYAAQp0Bn7zAEAAAAAA.Ellairis:BAABNQAECn8bAAIZAAgKnBUjjwACAgAZAAgKnBUjjwACAgAAAA==.Ellesperis:BAAANQAECgcIDQAAAA==.Ellumon:BAAANQAECgEIAQAAAA==.Elyana:BAAANQAECgYIDwAAAA==.Elyna:BAAANQADCgYIBgABNQAECggIJQAgACUVAA==.Elyssarelsia:BAABNQAECn8bAAMbAAYKmggiYgAkAQAaAAYKUAfWMAAyAQAbAAYKdAYiYgAkAQAAAA==.',
Em='Emergnc:BAAANQADCgQIBAAAAA==.',
En='Enubiuz:BAAANQAECgMIAwAAAA==.',
Er='Eragôn:BAABNQAECn8YAAISAAgKvxC0GQCrAQASAAgKvxC0GQCrAQAAAA==.Erdrus:BAAANQADCggICAABNQAECggIHgAGAJwbAA==.Erinyes:BAAANQAECgUIDwAAAA==.',
Es='Estee:BAAANQAECgcICgAAAA==.',
Et='Ethyl:BAAANQADCgEIAQAAAA==.',
Ex='Exarkune:BAAANQADCgYIBgAAAA==.Executioner:BAAANQAECgQICQAAAA==.',
Fa='Falafel:BAAANQADCggICAAAAA==.Faque:BAAANQADCgcIBwAAAA==.Fatfish:BAAANQADCggIBQAAAA==.Fatty:BAABNQAECn8rAAMBAAkKahLYFwD9AQABAAkKahLYFwD9AQAhAAEKAABzbQAsAAAAAA==.',
Fe='Feargasm:BAAANQABCgMIBQAAAA==.Felscream:BAAANQADCgcIDAAAAA==.Fenja:BAABNQAECn8yAAIVAAkKphazSQBMAgAVAAkKphazSQBMAgAAAA==.Feul:BAABNQAECn87AAIEAAkKfBt0PgBjAgAEAAkKfBt0PgBjAgAAAA==.Feyded:BAABNQAECn8aAAIDAAYK/hgGUACyAQADAAYK/hgGUACyAQAAAA==.Feylis:BAAANQADCgUIBQABNQAECggIHgANADcUAA==.',
Fh='Fhara:BAAANQAECgIIAgAAAA==.',
Fi='Fiasko:BAABNQAECn8iAAIcAAgKHRwabABKAgAcAAgKHRwabABKAgAAAA==.Fiir:BAAANQADCggIEwAAAA==.Finebaum:BAAANQADCgYIBgAAAA==.Firehose:BAAANQADCgUIBQABNQAECgkJJAALADUbAA==.Firesworn:BAAANQAECgUIBwAAAA==.Fizbang:BAAANQADCgQIBQAAAA==.',
Fl='Flippÿ:BAAANQAECgIIAwAAAA==.Flowerpower:BAAANQAECgMIAwAAAA==.Fluffythecup:BAABNQAECn8aAAISAAYKGhUyGgCjAQASAAYKGhUyGgCjAQAAAA==.',
Fm='Fmliplaygoat:BAAANQAECgUIDQAAAA==.',
Fo='Foreverdead:BAAANQADCgQIBwAAAA==.Formidonis:BAABNQAECn8wAAMLAAkKaSGXCgB2AwALAAkKaSGXCgB2AwANAAIKGhEiVwB4AAAAAA==.Foxyboo:BAAANQADCgYICwAAAA==.Foxylady:BAAANQADCgIIAgAAAA==.',
Fr='Frieddough:BAAANQAECgQIBAAAAA==.Frizix:BAAANQAECgEIAwAAAA==.Frostlady:BAAANQADCgUIBQAAAA==.Frostyna:BAABNQAECn8mAAMdAAkKWhjucQCaAgAdAAkKWhjucQCaAgAfAAIK/xFtOABZAAAAAA==.',
Fu='Fubber:BAABNQAECn8qAAIDAAkKRh7pEgAUAwADAAkKRh7pEgAUAwAAAA==.Fulgur:BAABNQAECn8dAAIbAAgKQQ4+OADvAQAbAAgKQQ4+OADvAQAAAA==.Funsizegurly:BAABNQAECn8xAAIdAAkKwhnwYgC4AgAdAAkKwhnwYgC4AgAAAA==.Furrgie:BAAANQAECgQIBQAAAA==.',
['Fâ']='Fâbio:BAAANQAECgMIAwAAAA==.',
Ga='Gallypotter:BAABNQAECn8ZAAICAAYKhRR5uQCMAQACAAYKhRR5uQCMAQAAAA==.Garygabagool:BAABNQAECn8gAAIWAAkK5B9XCADyAgAWAAkK5B9XCADyAgAAAA==.Gawdshamit:BAABNQAECn8nAAMEAAcKfxNCeACfAQAEAAcKfxNCeACfAQAVAAQKtAKgAAGGAAAAAA==.',
Ge='Gemcutter:BAAANQAECgQIBQAAAA==.Geoffreey:BAAANQAECgQICwAAAA==.',
Gh='Ghakk:BAAANQADCgYICAAAAA==.Ghostmane:BAAANQADCgIIAgAAAA==.Ghostorc:BAAANQAECgYIEAAAAA==.',
Gi='Gichidolo:BAAANQADCgEIAQAAAA==.Giegs:BAAANQAECgUICgAAAA==.',
Gl='Glockcoma:BAAANQADCgUIBAAAAA==.',
Gn='Gnatytoop:BAABNQAECn80AAIcAAkKFh6ONQDpAgAcAAkKFh6ONQDpAgAAAA==.Gnawrly:BAABNQAECn8dAAMFAAgKkRNOEgDXAQAFAAcK6xVOEgDXAQAPAAYK9gm+RAACAQAAAA==.',
Go='Goku:BAAANQADCggICAABNQAECgkJNgAGAMshAA==.Gonzo:BAABNQAECn8lAAMgAAgKJRXIEQAHAgAgAAgKJRXIEQAHAgAcAAIKUQRFQAFJAAAAAA==.Goodgirl:BAAANQAECgYIEAABNQAECggIDQAYAAAAAA==.Goodgurl:BAAANQAECggIDQAAAA==.Gormo:BAAANQADCgMIAwAAAA==.Govrek:BAAANQAECgYIEwAAAA==.',
Gr='Greenstone:BAAANQADCgcIDwAAAA==.Gretchn:BAAANQADCgQIBAAAAA==.Gricavent:BAAANQAECgQIBAAAAA==.Grobyc:BAAANQAECgUIBwAAAA==.Grïm:BAABNQAECn8qAAIfAAkKmB3LAwD9AgAfAAkKmB3LAwD9AgAAAA==.',
Gt='Gtfobubble:BAAANQAECgYICgAAAA==.Gtfolava:BAAANQADCgcIDAAAAA==.',
Gu='Guldont:BAAANQAECgQIBgAAAA==.',
Ha='Hankering:BAAANQAECgIIAwABNQAECgkJJgAKABsZAA==.Hankopher:BAABNQAECn8mAAQKAAkKGxl6KABPAgAKAAkK9RZ6KABPAgADAAcKUhbJWgCEAQAUAAQK2xNmiQD5AAAAAA==.Hanziè:BAAANQAECgUIEQAAAA==.Haptics:BAABNQAECn8xAAMbAAkKLyO1CABKAwAbAAkKrx61CABKAwAaAAUKhSS9GgD/AQAAAA==.Harbinger:BAAANQADCgMIAwAAAA==.Harmonix:BAAANQAECgUIDQAAAA==.Hasbin:BAAANQADCgcIEAAAAA==.Hatzel:BAABNQAECn8oAAIEAAkKaB6UHAD5AgAEAAkKaB6UHAD5AgAAAA==.',
He='Heaf:BAABNQAECn8bAAIVAAgKdSKPIQABAwAVAAgKdSKPIQABAwAAAA==.Hecateis:BAAANQAECgQIBQAAAA==.Heenan:BAAANQAECgYIDwAAAA==.Hellhaunt:BAAANQAECgUICgAAAA==.Hellstar:BAAANQADCggIHQAAAA==.Hemdh:BAAANQADCggIDgABNQAFFAcIEAAbAHoZAA==.Herukas:BAAANQAECgUIEgAAAA==.Hexsteele:BAAANQAECggIEQABNQAFFAYIGwAVAL4iAA==.',
Hi='Hick:BAAANQADCggICAAAAA==.Higanbana:BAAANQAECgQIBAABNQAECggIEQAYAAAAAA==.Hikons:BAAANQAECgEIAQABNQAECgkJKwABAGoSAA==.',
Ho='Hohiro:BAAANQADCgcIDgAAAA==.Holdmybear:BAAANQAECgQIDQAAAA==.Holyblood:BAAANQAECgQICgAAAA==.Holyfudge:BAAANQAECgIIAwABNQAECggIEgAYAAAAAA==.Holyhyper:BAABNQAECn8kAAIZAAkKxh8hKgAcAwAZAAkKxh8hKgAcAwAAAA==.Holyness:BAAANQADCgEIAQAAAA==.Holywaddles:BAAANQAECgIIAwAAAA==.',
Hr='Hrinnu:BAABNQAECn8hAAIJAAkKMRw1GgANAwAJAAkKMRw1GgANAwAAAA==.',
Ht='Htownshawdo:BAABNQAECn8eAAIgAAgKywgDHgBgAQAgAAgKywgDHgBgAQAAAA==.',
Hu='Huevocutter:BAAANQADCggIEAAAAA==.Huntardftw:BAAANQAECgMIAwAAAA==.Huntressa:BAAANQADCgYIBgAAAA==.Huntwick:BAAANQAECgQICAAAAA==.Hurkaj:BAAANQAECgQICwAAAA==.Huwest:BAAANQAECgEIAQAAAA==.',
['Hü']='Hünterrific:BAAANQADCggIDQAAAA==.',
Ic='Icanhealyou:BAABNQAECn82AAMGAAkKyyG/DwBGAwAGAAkKcSC/DwBGAwAIAAYKRRxGCQDCAQAAAA==.',
Il='Illusk:BAAANQAECgIJBQABNQAECggIIgAcAB0cAA==.',
In='Incisor:BAAANQADCgYIBgABNQAECggIGwAMAAQWAA==.Incline:BAAANQAECgQIBAAAAA==.Inola:BAAANQAECgMIAwAAAA==.Inoo:BAAANQAECggIEwAAAA==.',
Ir='Irishhammer:BAABNQAECn8ZAAIgAAYKqhgrGQCbAQAgAAYKqhgrGQCbAQAAAA==.',
Is='Isvnpcdhg:BAAANQAECgMIBQAAAA==.',
It='Itkovien:BAAANQAECgUIBQAAAA==.',
['Iá']='Ián:BAABNQAECn8lAAMNAAkKPiA6HwB0AQALAAcK8R5/XQA7AgANAAQKBR46HwB0AQAAAA==.',
Ja='Jackmeioff:BAAANQADCgMIAwAAAA==.Janq:BAABNQAECn8wAAIVAAkKCBhMOgCKAgAVAAkKCBhMOgCKAgAAAA==.Jayde:BAAANQADCgUIBgAAAA==.',
Je='Jellyfish:BAAANQAECgUIBwAAAA==.Jerrodsmage:BAAANQAECgQICAAAAA==.Jezbrez:BAAANQAECgUIDwAAAA==.',
Ji='Jimmycricket:BAAANQAECgYIDAAAAA==.Jinz:BAABNQAECn8VAAIbAAcKLwxzSQCYAQAbAAcKLwxzSQCYAQABNQAECggILwAZAFMgAA==.Jinzu:BAABNQAECn8vAAIZAAgKUyB5PwDUAgAZAAgKUyB5PwDUAgAAAA==.Jizzledizzle:BAAANQAECgQICQABNQAECggIEQAYAAAAAA==.',
Jo='Jono:BAAANQAECgQIBgAAAA==.Jordyne:BAAANQADCgMIAwAAAA==.',
Jp='Jphlip:BAABNQAECn8kAAMGAAgKbBmwTgA1AgAGAAgKbBmwTgA1AgAIAAQKyQ4CFQDXAAAAAA==.Jpmagi:BAACNQAFFH8MAAIdAAUKzhmbFwC2AQAdAAUKzhmbFwC2AQA1AAQKfyEAAh0ACQrRH0tPAOMCAB0ACQrRH0tPAOMCAAAA.',
Ju='Juice:BAAANQAECgUICwAAAA==.Juisi:BAABNQAECn8iAAIbAAgKch7gHACTAgAbAAgKch7gHACTAgAAAA==.Jullene:BAAANQADCgcIDQAAAA==.Justania:BAAANQADCgEIAQABNQAECgkJKAAJAMIFAA==.',
['Jô']='Jô:BAAANQAECgEIAQABNQAFFAIIBQAWAJ0dAA==.',
Ka='Kaeloth:BAABNQAECn8lAAIZAAkKYR0PQgDLAgAZAAkKYR0PQgDLAgAAAA==.Kagayoshi:BAAANQADCgIIAgAAAA==.Kainen:BAAANQABCgQICQAAAA==.Kalal:BAAANQAECggIEgAAAA==.Kalebmonk:BAAANQADCggJDwABNQAECgkJJgAZAKATAA==.Kalebpal:BAABNQAECn8mAAIZAAkKoBMPfwAmAgAZAAkKoBMPfwAmAgAAAA==.Kamtano:BAABNQAECn8aAAIUAAYKbg6HbQBZAQAUAAYKbg6HbQBZAQAAAA==.Kavaliro:BAAANQADCgMIAwAAAA==.Kayaane:BAAANQABCgYICAAAAA==.Kayaanu:BAABNQAECn8nAAMdAAgK+yPSWwDIAgAdAAcKgiTSWwDIAgAfAAEKVSGVOABZAAAAAA==.Kazimiraci:BAAANQADCggICAAAAA==.',
Ke='Kegsmasher:BAAANQADCggICAAAAA==.Kellholy:BAACNQAFFH8FAAIZAAIKMhnkIACZAAAZAAIKMhnkIACZAAA1AAQKfyEAAhkACQrXJNYPAIoDABkACQrXJNYPAIoDAAAA.',
Kh='Khraden:BAAANQADCggICAAAAA==.Khyzer:BAAANQADCgYIBgABNQAECgkJLwADABwdAA==.',
Ki='Kickya:BAAANQADCgEIAQAAAA==.Kidkill:BAAANQADCgIIAgAAAA==.Kikii:BAAANQAECgYICgAAAA==.Killaboy:BAAANQADCgEIAQAAAA==.Killstar:BAAANQADCgUIFgABNQADCggIEQAYAAAAAA==.Kirke:BAAANQADCgIIAgABNQAECgEIAQAYAAAAAA==.Kirriana:BAAANQAECgIIBQAAAA==.Kisara:BAAANQADCgIIAgABNQAECggIHgAGAJwbAA==.',
Kk='Kkitty:BAAANQAECgQIBwAAAA==.',
Kl='Klash:BAAANQAECgMIAwAAAA==.Kleddus:BAAANQAECgQIDgAAAA==.Kletas:BAAANQAECgUIBgAAAA==.Kletus:BAAANQAECgQIBgAAAA==.',
Kn='Knokkpriest:BAAANQAECggIEQAAAA==.Knokkshee:BAAANQADCgIIAwAAAA==.',
Ko='Kobs:BAAANQADCgUIBQAAAA==.Konflict:BAAANQAECgcIBQABNQAECgkJIQAdAGkcAA==.Kopy:BAAANQAECgUIDAABNQAECgkJIQAdAGkcAA==.Korvash:BAAANQAECgYIEAAAAA==.',
Kr='Kroitz:BAAANQADCgUIBQAAAA==.Kromgol:BAAANQAFFAEIAQAAAA==.Krupp:BAAANQAECgEIAQAAAA==.',
Ku='Kujaku:BAABNQAECn8aAAIQAAYKnA6yYgA/AQAQAAYKnA6yYgA/AQAAAA==.Kushov:BAAANQADCgMIAwAAAA==.',
Kw='Kwende:BAAANQAECgYICAAAAA==.',
Ky='Kyela:BAABNQAECn8aAAIJAAYK9AR3vAD/AAAJAAYK9AR3vAD/AAAAAA==.Kyrtion:BAABNQAECn8iAAQMAAkK+RYzIABJAgAMAAkK+RYzIABJAgAeAAEKAADdmgAkAAAiAAEKAAAfOQAZAAAAAA==.',
['Kä']='Kätsuö:BAAANQAECgMIAwABNQAECggIEQAYAAAAAA==.',
['Kø']='Kørupted:BAAANQAECgUIEQAAAA==.',
La='Lamiisa:BAAANQAECgQICAAAAA==.Lanaris:BAAANQAECgUIDQAAAA==.Laurandrel:BAAANQAECgYIEAAAAA==.Laved:BAABNQAECn8uAAMQAAkKhSPhBQCmAwAQAAkKhSPhBQCmAwAPAAQKLhybOgBGAQAAAA==.Lawgi:BAABNQAECn8yAAIjAAkK/xraEQCAAgAjAAkK/xraEQCAAgAAAA==.Lawliet:BAAANQABCgIIAgAAAA==.',
Ld='Ldkillem:BAAANQAECgUIDAABNQAECggIJAALACEcAA==.Ldkils:BAAANQADCgIIAgAAAA==.Ldlockem:BAABNQAECn8kAAMLAAgKIRyLeQDyAQALAAYKNxyLeQDyAQANAAIK9RvISACkAAAAAA==.',
Le='Lewìn:BAABNQAECn8UAAICAAcKJiadKwDpAgACAAcKJiadKwDpAgAAAA==.',
Li='Likäbäws:BAAANQADCgYICAAAAA==.Lilitü:BAAANQADCggICQAAAA==.Lilpoopsie:BAAANQAECgcIBwAAAA==.Lilshadow:BAAANQADCgIIAgAAAA==.Lilwascal:BAAANQAECgUICAAAAA==.Lilya:BAAANQADCgYIBgABNQAECgEIAQAYAAAAAA==.Linatheslayr:BAAANQADCggIDQAAAA==.Linossa:BAABNQAECn8jAAIdAAgK+hI1rwAjAgAdAAgK+hI1rwAjAgAAAA==.Lithiris:BAABNQAECn8oAAMJAAkKwgUyhQCIAQAJAAkKwgUyhQCIAQAZAAUKCQXUNgHBAAAAAA==.',
Ll='Llonso:BAAANQADCgUIBQAAAA==.',
Lo='Loba:BAAANQABCgEIAQABNQAECgcIGAAIAJAKAA==.Lockjam:BAAANQAECgEIAQAAAA==.Lookiezi:BAABNQAECn8aAAIJAAkK5hu9IgDfAgAJAAkK5hu9IgDfAgAAAA==.Lovemuffîn:BAABNQAECn8fAAIcAAkKQxXIegAkAgAcAAkKQxXIegAkAgAAAA==.',
Lu='Lucidonis:BAABNQAECn8YAAIPAAgKdRJGMwB8AQAPAAgKdRJGMwB8AQAAAA==.Luminaconri:BAAANQAECgQICQAAAA==.',
Ly='Lystia:BAABNQAECn8VAAIZAAcKXxrRjgADAgAZAAcKXxrRjgADAgAAAA==.',
['Læ']='Læncelot:BAAANQAECgMIAwAAAA==.',
Ma='Madriel:BAAANQAECgcICQAAAA==.Maelk:BAAANQAECgMIAwABNQAFFAIIBQAWAJ0dAA==.Mafanya:BAAANQABCgYICgAAAA==.Magento:BAABNQAECn8qAAMdAAkKah4eZQC0AgAdAAkKfRkeZQC0AgAfAAMKcCGdHAAHAQAAAA==.Mailla:BAAANQAECgUIBQAAAA==.Maladie:BAABNQAECn8kAAIUAAgKsxLwSwDiAQAUAAgKsxLwSwDiAQAAAA==.Malvaron:BAAANQADCgYICwAAAA==.Mauna:BAAANQAECgUIBQAAAA==.Mavzy:BAABNQAECn8lAAIOAAkKRBAiBwAuAgAOAAkKRBAiBwAuAgAAAA==.Mayberav:BAAANQADCgYIBgAAAA==.',
Mc='Mcbubbies:BAABNQAECn8eAAMHAAkKuSKQCQBFAwAHAAkKuSKQCQBFAwAGAAQKwRhSqQAUAQAAAA==.Mcfknkfc:BAAANQAECgUICwAAAA==.',
Me='Meeyo:BAAANQADCgEIAQAAAA==.Megamanmeat:BAAANQAECggIAgAAAA==.Megaroni:BAAANQADCgYIBgAAAA==.Melpomne:BAAANQADCgcICgAAAA==.Menerva:BAAANQAECggIEAAAAA==.',
Mi='Micti:BAABNQAECn8lAAINAAgKJRRgCwBAAgANAAgKJRRgCwBAAgAAAA==.Milamber:BAABNQAECn8fAAMdAAgKlQcX7QCtAQAdAAgKkQcX7QCtAQAfAAEKYgN/SwAtAAAAAA==.Minionrogue:BAAANQAECgIJAwAAAA==.Minyon:BAABNQAECn8nAAIHAAgKPiR+CgA4AwAHAAgKPiR+CgA4AwAAAA==.Miruna:BAAANQAECgQIBwAAAA==.Missiles:BAAANQADCgIIAgAAAA==.Missing:BAAANQAECgQIDAABNQAECggIEgAYAAAAAA==.Missmage:BAAANQADCggICgAAAA==.',
Mo='Mogge:BAAANQAECgQIBAABNQAECggILQAgAM4dAA==.Mommadragon:BAAANQAECgUIEgAAAA==.Monkybrewstr:BAAANQADCgEIAQAAAA==.Monsterflexx:BAAANQAECgQIBAAAAA==.Monsterpal:BAAANQAECgEIAQAAAA==.Moosè:BAAANQADCgYIFQAAAA==.',
Mu='Mugron:BAABNQAECn8hAAIgAAgKkyM3BQAjAwAgAAgKkyM3BQAjAwABNQAFFAcIIwADADcgAA==.Murotarimp:BAAANQAECgEIAQAAAA==.',
My='Mydkfelloff:BAAANQAECggIAgABNQAECggIFwAVAGIfAA==.Myronath:BAAANQADCgMIAwABNQAECgUICgAYAAAAAA==.Mystafire:BAAANQAECgIIAwAAAA==.Mythpriest:BAAANQAECgIIAgABNQAECggIHQAJAKUQAA==.',
Na='Nadlug:BAAANQADCgcIEwABNQAECgcIBwAYAAAAAA==.Naki:BAAANQAECgYICgABNQAECggIIAAdAAEYAA==.Naljubuites:BAAANQABCgYJDQAAAA==.Naradda:BAAANQADCgUIBQAAAA==.Narsissa:BAAANQADCgQIBAAAAA==.Narìko:BAAANQAECggIEQAAAA==.Nazra:BAAANQADCgMIAwAAAA==.',
Ne='Neblig:BAAANQADCgcIBwAAAA==.Neebstrasza:BAAANQAECgEIAQAAAA==.Nensuk:BAAANQAECgQICAAAAA==.Neska:BAAANQAECgUIBQAAAA==.Newdamda:BAAANQAECgYIDAAAAA==.',
Ni='Nicodormus:BAAANQAECgIJAgAAAA==.Nicolius:BAABNQAECn8mAAMJAAkKzhtxJgDOAgAJAAkKzhtxJgDOAgAjAAIKxgEgbAA3AAAAAA==.Ningenalah:BAABNQAECn8lAAMUAAkKASPWFwD9AgAUAAgK5SPWFwD9AgAKAAQK+yDVTwBsAQAAAA==.Ningenurion:BAAANQAECgIIAwABNQAECgkJJQAUAAEjAA==.Nippÿ:BAABNQAECn8iAAMfAAkKCBaDBwB1AgAfAAkKCBaDBwB1AgAdAAQKDwe6cAHXAAAAAA==.Niryûl:BAAANQADCgYIBgAAAA==.',
No='Norav:BAABNQAECn8mAAMVAAkKgh/8FgA8AwAVAAkKgh/8FgA8AwAEAAEK6Qd4GQE0AAAAAA==.Nordryd:BAAANQAECgQIBAABNQAFFAYIDQATAKEKAA==.Nordryde:BAACNQAFFH8NAAITAAYKoQoJCQCgAQATAAYKoQoJCQCgAQA1AAQKfxwABBMACQpPFAsYADkCABMACQpPFAsYADkCABIAAgreIMwuAKIAACQAAQoaErAjADUAAAAA.Nordrydm:BAAANQAECgYICgABNQAFFAYIDQATAKEKAA==.Notfrïendly:BAAANQADCgIIAgAAAA==.Novamortis:BAAANQADCgQJBAAAAA==.',
Nu='Nuabo:BAAANQAECgIIAgABNQAECgkJMgADANIfAA==.Numb:BAAANQADCggICAAAAA==.',
['Ní']='Níghtmäre:BAAANQAECgUIBQAAAA==.',
Of='Offensive:BAAANQAECgQIBAAAAA==.',
Ol='Olayhahla:BAAANQAECgYICQAAAA==.',
Op='Opalausia:BAAANQADCgYIBgAAAA==.',
Or='Oregano:BAABNQAECn8xAAIWAAkKjyS8AADNAwAWAAkKjyS8AADNAwAAAA==.',
Os='Osyrus:BAAANQADCgEIAQAAAA==.',
Ou='Ourania:BAAANQADCgEIAQAAAA==.',
Ov='Overkill:BAAANQABCgUIBgAAAA==.',
Pa='Padreberk:BAAANQADCgYIEgAAAA==.Painremains:BAAANQADCgcIDAAAAA==.Pantyfa:BAAANQADCgIIAwAAAA==.Panzon:BAAANQADCgUIBQAAAA==.',
Pe='Pekkie:BAAANQAECgUIDgAAAA==.Penpineapple:BAAANQAECgMIBAAAAA==.Penthesilea:BAAANQAECgEIAQAAAA==.Perchance:BAAANQABCgIIAgAAAA==.Persnickity:BAAANQADCggICAAAAA==.Pestcontrol:BAAANQAECgEIAQAAAA==.',
Ph='Phallon:BAABNQAECn8WAAIFAAcKRRZZEgDXAQAFAAcKRRZZEgDXAQAAAA==.Phat:BAAANQAECgIIAgABNQAECgkJKwABAGoSAA==.',
Pi='Pidi:BAAANQAECgcIDQABNQAECgkJMQAdAMIZAA==.Pioree:BAABNQAECn8qAAQTAAkKFxkLFQBhAgATAAgKeBoLFQBhAgASAAcK6ReiFQDvAQAkAAQKIgZmGQCjAAAAAA==.Pixen:BAAANQAECgQIBwABNQAECgkJOQALAI8ZAA==.',
Po='Ponglenis:BAAANQADCggIEAABNQAECggIGAAVAOQZAA==.Pookiebear:BAAANQADCgMIAwAAAA==.Poonany:BAAANQAECgEIAQAAAA==.Pootnuts:BAAANQADCgIIAgAAAA==.',
Pr='Prandal:BAAANQAECgEIAQAAAA==.Pregzuel:BAAANQADCgUIBgAAAA==.Projecthorde:BAABNQAECn8YAAIUAAcK9gmOcwBFAQAUAAcK9gmOcwBFAQAAAA==.Pronouns:BAAANQADCgEIAQABNQAECgkJIQADAFMeAA==.',
Py='Pyroganus:BAAANQADCgYIBgABNQAECgUIEgAYAAAAAA==.Pyyke:BAAANQAECgUIBQAAAA==.',
Qu='Quanzanon:BAABNQAECn8hAAIQAAkK0QiLTACsAQAQAAkK0QiLTACsAQAAAA==.Quizhik:BAAANQAECgEIAQABNQAECggIEgAYAAAAAA==.',
Qw='Qwerty:BAAANQADCgUIBQABNQAECgkJKwABAGoSAA==.',
Ra='Rachelrae:BAABNQAECn8zAAIGAAkKOhEmUgApAgAGAAkKOhEmUgApAgAAAA==.Radbrother:BAAANQABCgIIAgAAAA==.Raffikki:BAAANQADCgIIAgAAAA==.Rag:BAAANQAECgUIEAAAAA==.Ralphy:BAAANQAECgUIEgAAAA==.Ramenwrapz:BAABNQAECn8cAAIGAAgKwR03JQDUAgAGAAgKwR03JQDUAgAAAA==.Raryees:BAABNQAECn8mAAQKAAkKWiErMQAZAgAKAAkKsRYrMQAZAgADAAYKTx1fQwDrAQAUAAYKLR34SgDmAQAAAA==.Raveñous:BAAANQADCgMIAwABNQAFFAUICgAJABwTAA==.',
Re='Reddynon:BAABNQAECn8lAAMkAAgKuRhSCAARAgAkAAcK7xdSCAARAgASAAcKvxaSFQDxAQAAAA==.Reginald:BAAANQADCgIIAgABNQAECgcIGQAFAPciAA==.Relin:BAABNQAECn8rAAMXAAkKMSJ/CgAtAwAXAAkKMSJ/CgAtAwACAAEKAAA3OQFpAAAAAA==.Relinbear:BAAANQADCgcIBwABNQAECgkJKwAXADEiAA==.Relse:BAAANQADCgYICwAAAA==.Renika:BAAANQAECgcJDwAAAA==.Renmazuo:BAAANQAECgcIDwAAAA==.Renrax:BAAANQAECgIIAgAAAA==.Reopal:BAAANQADCgUIBQAAAA==.Resperea:BAAANQAECgQICQAAAA==.Respwar:BAAANQADCgcIBwAAAA==.Revadin:BAAANQAECggICAAAAA==.Revwild:BAAANQAECgQICQAAAA==.',
Ri='Ricassou:BAABNQAECn8XAAIlAAcKLh3TDAAwAgAlAAcKLh3TDAAwAgAAAA==.Rivendell:BAABNQAECn8tAAIZAAkKsiNSEgB9AwAZAAkKsiNSEgB9AwAAAA==.Rivit:BAAANQADCgMIAwAAAA==.',
Ro='Roonkmc:BAABNQAECn8eAAICAAgKxQfqmQDPAQACAAgKxQfqmQDPAQABNQADCgYICwAYAAAAAA==.Rorynne:BAAANQAECgYIDgAAAA==.',
Rr='Rrubio:BAAANQAECgUIDAAAAA==.',
Ru='Rucy:BAAANQABCgMIAwAAAA==.Ruend:BAAANQADCgYIBgAAAA==.',
Ry='Ryndkmc:BAAANQADCggIDgABNQADCgYICwAYAAAAAA==.Ryuujin:BAAANQAECgIIAwAAAA==.',
['Ré']='Réflex:BAAANQADCgQIBgAAAA==.Réfléx:BAAANQAECgEIAQAAAA==.',
['Ró']='Ródin:BAAANQAECgYIDAABNQAFFAYIGQAHAP8eAA==.',
Sa='Sabrewulf:BAAANQAECgQIBQAAAA==.Saellen:BAAANQAECgEIAQAAAA==.Saeya:BAAANQADCgMIBAAAAA==.Sakurai:BAABNQAECn8ZAAIbAAYKESQXJQBdAgAbAAYKESQXJQBdAgAAAA==.Salorllis:BAABNQAECn8cAAIhAAcK6BYCKwC/AQAhAAcK6BYCKwC/AQAAAA==.Sanso:BAAANQAECgIJAgABNQAECgkJJgAKABsZAA==.Sarah:BAAANQADCggIAgAAAA==.Saristia:BAABNQAECn8aAAICAAYK4x8igQAHAgACAAYK4x8igQAHAgAAAA==.Saveu:BAABNQAECn8hAAMGAAgK/xj8VwAWAgAGAAcKSxv8VwAWAgAHAAEKAABHgwAkAAAAAA==.',
Sc='Schannon:BAAANQAECgQIBQAAAA==.Screampies:BAAANQAECgQIBgAAAA==.',
Se='Seagulls:BAEANQAECgIIBQAAAA==.Seayaa:BAABNQAECn8aAAICAAYKDxMqrwChAQACAAYKDxMqrwChAQAAAA==.Seiryu:BAAANQADCgMIAwAAAA==.Selindia:BAABNQAECn8ZAAIJAAYKJQI53wC9AAAJAAYKJQI53wC9AAAAAA==.Sellsword:BAAANQADCgMIAwAAAA==.',
Sf='Sfx:BAAANQADCggIDAABNQAFFAYIEgACAEoeAA==.',
Sg='Sgt:BAABNQAECn8YAAQbAAgKoREcNAAFAgAbAAgKoREcNAAFAgAaAAQK0gX5OwDRAAAmAAIKDAM1GgA+AAAAAA==.',
Sh='Shadowydeath:BAAANQADCgYIEAAAAA==.Shaedee:BAABNQAECn8jAAIHAAkKbhfOFgCiAgAHAAkKbhfOFgCiAgAAAA==.Shaina:BAAANQABCgIIAgAAAA==.Shallon:BAAANQAECgcIDwAAAA==.Shamalott:BAAANQABCgQIBAAAAA==.Shammpoo:BAAANQABCgUIBgAAAA==.Shammyshaga:BAAANQAECgYIDwAAAA==.Shapest:BAAANQADCgQIBAAAAA==.Sheeple:BAAANQAECgQIBAAAAA==.Shelby:BAAANQAECgUICAAAAA==.Shilihu:BAAANQAECgUICQAAAA==.Shinukishin:BAABNQAECn8fAAIUAAkK7iLEDQBKAwAUAAkK7iLEDQBKAwAAAA==.Shiu:BAAANQADCgYICgAAAA==.Shnottz:BAABNQAECn8fAAIdAAkKwhQ4jgBiAgAdAAkKwhQ4jgBiAgAAAA==.Shocknar:BAAANQADCgIIAgAAAA==.Shorzy:BAABNQAECn8lAAIMAAgKFB41FADDAgAMAAgKFB41FADDAgAAAA==.Shredzdh:BAABNQAECn8qAAIMAAkKsh9QCgA0AwAMAAkKsh9QCgA0AwAAAA==.Shrine:BAAANQADCggICAAAAA==.',
Si='Sienar:BAAANQAECgQIBgAAAA==.Sillybone:BAAANQADCgEIAQAAAA==.Simulacra:BAAANQAECgIIAgAAAA==.Sitonmytotem:BAAANQADCggIDgAAAA==.Sixteen:BAAANQADCgUICgAAAA==.',
Sl='Sloppyblades:BAAANQADCggICQAAAA==.Slu:BAACNQAFFH8YAAMdAAYKVxnADgD8AQAdAAYKVxnADgD8AQAfAAEKmgawFQA9AAA1AAQKfyEAAh0ACQrbI6U3ABkDAB0ACQrbI6U3ABkDAAE1AAQKCQkkAAsANRsA.',
Sm='Smashinsmith:BAABNQAECn8dAAIcAAkKaR4OMgD1AgAcAAkKaR4OMgD1AgAAAA==.Smorgasbord:BAAANQAECgIIAgAAAA==.',
Sn='Snackpack:BAAANQAECgYIEAAAAA==.Sneakodemus:BAAANQAECgEJAQAAAA==.Snockerz:BAAANQADCggICAAAAA==.Snowblind:BAAANQAECgEIAQAAAA==.Snowdancer:BAAANQAECgMIBgAAAA==.',
So='Sokkmage:BAAANQADCgYIDAAAAA==.Solnar:BAABNQAECn8YAAIHAAcKsARuSAD3AAAHAAcKsARuSAD3AAAAAA==.Somno:BAABNQAECn8yAAMMAAkKOx63DQAJAwAMAAkKOx63DQAJAwAiAAEKAAAGKABwAAAAAA==.Sonory:BAAANQAECgIIAgAAAA==.Sophea:BAAANQADCgYIHQAAAA==.Soska:BAAANQADCgYIEgAAAA==.Soulfly:BAAANQAECgUIDwAAAA==.Soulsabi:BAABNQAECn8cAAMLAAgK0yO5GAAiAwALAAgK0yO5GAAiAwANAAIKuRHqWAB0AAAAAA==.Soulshaper:BAAANQAECgQIBQAAAA==.',
Sp='Spectral:BAACNQAFFH8JAAIGAAUKVxG3EACHAQAGAAUKVxG3EACHAQA1AAQKfykAAgYACQp0IdknAMgCAAYACQp0IdknAMgCAAAA.Spicy:BAAANQADCgMJAwAAAA==.Spiritspawn:BAABNQAECn8dAAIEAAgKphYLWgD+AQAEAAgKphYLWgD+AQAAAA==.Spookyshark:BAAANQADCgQIBAAAAA==.Spoonman:BAACNQAFFH8FAAIPAAIK7QXWEQB9AAAPAAIK7QXWEQB9AAA1AAQKfysAAw8ACQrnE4whABcCAA8ACQrnE4whABcCABAAAQrFAuW5ACUAAAAA.Spåwnkîll:BAAANQADCgUIBQAAAA==.',
Sq='Squidheäd:BAAANQABCgYICAAAAA==.',
St='Stabystab:BAAANQAECgIIAgAAAA==.Stardrift:BAAANQADCggIEgAAAA==.Stare:BAAANQADCgIIAgABNQAECgkJJwAPAJgZAA==.Stellar:BAAANQADCgEIAQAAAA==.Stere:BAABNQAECn8nAAQPAAkKmBkJFACnAgAPAAkKmBkJFACnAgAQAAYK8hCOWwBfAQAFAAMKVAlGLgCZAAAAAA==.Stinggrayjr:BAABNQAECn8bAAMfAAgK3QtREACfAQAfAAgK3QtREACfAQAdAAIKTQGA0QErAAAAAA==.Stormhuff:BAAANQADCgUIBQAAAA==.Stärkiller:BAAANQADCgEIAQAAAA==.Stòrm:BAAANQADCgUIBgAAAA==.Stórm:BAAANQAECgIIAgAAAA==.',
Su='Sunderance:BAAANQADCgUIBgABNQAFFAIIBQAWAJ0dAA==.Sunlife:BAAANQAECggIEQAAAA==.Superhilock:BAACNQAFFH8FAAQOAAIKWgo2CwBPAAAOAAEKtQk2CwBPAAALAAEK/gqSQABJAAANAAEKoQhgIABIAAA1AAQKfy4ABAsACQptImM/AJECAAsABwqKIWM/AJECAA4AAwqgJHcQAEIBAA0AAwpKIZYsABsBAAAA.Supplesuckle:BAAANQABCgIIAgABNQAECgQIBgAYAAAAAA==.',
Sv='Svelesstiá:BAAANQADCgcIFAAAAA==.',
Sw='Sweetcreams:BAAANQADCgUIBQAAAA==.',
Sy='Sybrand:BAABNQAECn8vAAIDAAkKHB0dHgC/AgADAAkKHB0dHgC/AgAAAA==.Syrelliia:BAABNQAECn8oAAIbAAkKow1PNAAEAgAbAAkKow1PNAAEAgAAAA==.Syrenia:BAAANQABCgEIAQAAAA==.',
['Sæ']='Sævage:BAABNQAECn8dAAICAAgK0Rb9XABcAgACAAgK0Rb9XABcAgAAAA==.',
['Sø']='Sørta:BAABNQAECn8aAAIIAAYKEyYGBACWAgAIAAYKEyYGBACWAgAAAA==.',
Ta='Tae:BAAANQAECgIIAgAAAA==.Taigun:BAABNQAECn8aAAMZAAYKYBqYsAC4AQAZAAYKYBqYsAC4AQAJAAMKbgW/+gCBAAAAAA==.Talendar:BAAANQAECgUICgAAAA==.Tanktotem:BAAANQAECgUIBQAAAA==.Tarnac:BAAANQADCgYICwAAAA==.Tazorface:BAABNQAECn8hAAIDAAkKUx6/GADlAgADAAkKUx6/GADlAgAAAA==.',
Te='Techtonich:BAAANQAECgYICQAAAA==.Tehcakeman:BAAANQAECgIIAgABNQAECgkJHgALAHsWAA==.Terisa:BAAANQABCgIIAgAAAA==.Terkey:BAABNQAECn8xAAMGAAkK4R8sDwBKAwAGAAkK4R8sDwBKAwAIAAcKMhBkDABxAQABNQAFFAQIDgAfAGUPAA==.',
Th='Tharkash:BAABNQAECn8eAAIVAAgKyx18LQDEAgAVAAgKyx18LQDEAgAAAA==.Thedarktore:BAAANQADCgcIBwAAAA==.Thedocktore:BAAANQADCgYIBgAAAA==.Thedockwho:BAABNQAECn8eAAMVAAcKphK5ewCsAQAVAAcKWBK5ewCsAQAWAAQK9BCNJgDwAAAAAA==.Thedoctorwho:BAAANQAECgIIAgAAAA==.Theliarcy:BAABNQAECn8ZAAQGAAcKbx1VRwBNAgAGAAcK1BxVRwBNAgAIAAQKxhgwEAAkAQAHAAEKjAYYfwAqAAAAAA==.Thesaint:BAAANQADCgQIBAAAAA==.Thiccake:BAAANQADCgEIAQABNQAECgkJHgALAHsWAA==.Thirdeye:BAABNQAECn8pAAIPAAkKTR91CQAsAwAPAAkKTR91CQAsAwAAAA==.Thordendal:BAAANQADCgEIAQAAAA==.Thoxic:BAAANQAECgEIAQABNQAECgkJLwADABwdAA==.Thunderbuns:BAAANQAECgcIEAAAAA==.Thundrcat:BAAANQADCgIIAwAAAA==.',
Ti='Tiffaniie:BAAANQAECgEIAQAAAA==.Timidity:BAAANQAECggIDgAAAA==.Tinkerbelles:BAAANQADCgMIAwAAAA==.Tipz:BAAANQAECgQIBgAAAA==.Tiras:BAAANQADCgUIBQAAAA==.',
To='Toolip:BAABNQAECn8fAAIJAAgKVRjoSABBAgAJAAgKVRjoSABBAgAAAA==.Tornwraith:BAAANQAECgUIDQAAAA==.Towel:BAAANQADCgcIBwABNQAECggIJAANAAsYAA==.',
Tr='Traumademon:BAAANQABCggICwABNQADCggIEwAYAAAAAA==.Traumasdruid:BAAANQADCggIEwAAAA==.Traviana:BAAANQADCggIEwAAAA==.Trehuga:BAACNQAFFH8GAAIPAAMKaA5EDQDTAAAPAAMKaA5EDQDTAAA1AAQKfzcAAw8ACQpMHGsTAK4CAA8ACQpMHGsTAK4CABAAAQoAABOnAEUAAAAA.Trex:BAAANQADCgYIBgABNQAECgkJMgADANIfAA==.Trikky:BAAANQAECgIIBQAAAA==.Triso:BAABNQAECn8kAAILAAkKNRuXKQDbAgALAAkKNRuXKQDbAgAAAA==.Trixiie:BAAANQAECgUIBQAAAA==.Trochanter:BAAANQAECgQIBQAAAA==.Tronus:BAAANQAECggIEQABNQAECgkJIQAJADEcAA==.',
Ts='Tsukaar:BAABNQAECn8tAAIgAAgKzh2aCwB+AgAgAAgKzh2aCwB+AgAAAA==.',
Tu='Tutorialboss:BAACNQAFFH8XAAMXAAYKVB22CQCkAQAXAAUK4R62CQCkAQACAAIKIhcLHwC0AAA1AAQKfysAAxcACQroJAIHAF8DABcACQroJAIHAF8DAAIAAQoAADRVATkAAAAA.',
Tw='Twohorns:BAABNQAECn8vAAITAAkKkBTHFQBXAgATAAkKkBTHFQBXAgAAAA==.',
['Tâ']='Tâto:BAAANQABCgIIAgAAAA==.',
['Tö']='Töterfrieren:BAABNQAECn8nAAIfAAkKDA1sDADwAQAfAAkKDA1sDADwAQAAAA==.',
Ul='Ulrika:BAAANQAECgYICAAAAA==.Ultrön:BAABNQAECn8hAAIZAAgKGRu8YgBuAgAZAAgKGRu8YgBuAgAAAA==.',
Um='Umami:BAAANQADCgYIBgAAAA==.Umbryelle:BAAANQAECgQIBQAAAA==.',
Un='Undermaw:BAABNQAECn8xAAIJAAkKbyIfCQB+AwAJAAkKbyIfCQB+AwAAAA==.Unforgyven:BAAANQADCggIDAAAAA==.Unicron:BAAANQAECgMIBAAAAA==.',
Ur='Ursoulismine:BAAANQAECgQICgAAAA==.',
Va='Vaelianne:BAAANQAECgQIBAAAAA==.Vaesh:BAAANQAECgQIBgAAAA==.Vahyhunt:BAAANQADCggICAAAAA==.Valennah:BAAANQAECgQICQAAAA==.Valgaar:BAAANQAECgUIEQAAAA==.Vaneste:BAABNQAECn8aAAMLAAkK7xyfPgCTAgALAAgK3ByfPgCTAgANAAEKYx1CbgBBAAAAAA==.Vapelife:BAAANQABCgQIBAAAAA==.Vartlock:BAABNQAECn8pAAQLAAkKcR0QIgD5AgALAAkKcR0QIgD5AgANAAEK9BXbcwA6AAAOAAEKAAAXLgA5AAAAAA==.Vartrino:BAAANQAECgYIEwABNQAECgkJKQALAHEdAA==.',
Ve='Veganator:BAABNQAECn8sAAIQAAkK3xj0IADDAgAQAAkK3xj0IADDAgAAAA==.Veggies:BAAANQAECgIIAgAAAA==.Velani:BAAANQADCggJFgABNQAECggIHgAGAJwbAA==.Velynda:BAAANQAECgEIAQABNQAECggIHgANADcUAA==.Vendoralia:BAAANQAECgQICAAAAA==.Verifiedbot:BAAANQAECggIDgAAAA==.Verlant:BAABNQAECn8nAAIJAAgK9hCzZwDdAQAJAAgK9hCzZwDdAQAAAA==.',
Vi='Vicktor:BAAANQAECgUIBQAAAA==.Vinnyboombat:BAAANQABCgQIBAABNQADCgYICwAYAAAAAA==.Viraya:BAAANQAECgIIAgABNQAECgkJHwAcAEMVAA==.Virikae:BAAANQAECgYIDAAAAA==.Virâyâ:BAAANQADCgMIAwABNQAECgkJHwAcAEMVAA==.Vitus:BAAANQAECgMIAwAAAA==.',
Vl='Vladriel:BAAANQAECgYIDAAAAA==.',
Vo='Voidy:BAAANQAECgEIAQABNQAECgkJKwABAGoSAA==.Voljinn:BAAANQADCggIFQAAAA==.',
['Vá']='Vánlanthiriá:BAAANQADCgYIBgAAAA==.',
Wa='Waddlebottle:BAAANQAECgMIAwAAAA==.Wallock:BAAANQAECgQICgAAAA==.Wangdangg:BAAANQAECgIIAgAAAA==.War:BAABNQAECn8kAAIjAAkKAiJBAwCOAwAjAAkKAiJBAwCOAwABNQAECgkJIQAdAGkcAA==.Warfury:BAAANQAECgUICQAAAA==.Warrdruid:BAAANQADCgIIAgAAAA==.Watchnu:BAAANQAECgYIBwAAAA==.',
Wh='Whimsy:BAAANQADCggIHQABNQAFFAIIBQAWAJ0dAA==.Whät:BAAANQADCggJHAABNQAECggIEQAYAAAAAA==.',
Wi='Willowhite:BAABNQAECn8eAAICAAcKYwwdrACoAQACAAcKYwwdrACoAQAAAA==.',
Wo='Wockyslush:BAAANQADCgUIBQAAAA==.',
Wu='Wubers:BAABNQAECn8XAAIJAAgKxBsvNACRAgAJAAgKxBsvNACRAgABNQAECggIFwAVAGIfAA==.Wubwub:BAABNQAECn8XAAIVAAgKYh/6LwC4AgAVAAgKYh/6LwC4AgAAAA==.Wulfjin:BAABNQAECn8cAAMCAAgKWhvfVgBrAgACAAgKUBvfVgBrAgAnAAcKRRTuCAC0AQAAAA==.',
Xa='Xalia:BAAANQADCgQIBQAAAA==.',
Xe='Xellie:BAAANQADCgUIBgAAAA==.',
Xu='Xua:BAAANQAECgEIAgAAAA==.',
['Xë']='Xërík:BAAANQAECgMICAAAAA==.',
Ye='Yeyou:BAAANQADCgcIBwAAAA==.',
Yo='Yopan:BAAANQAECgYIDQAAAA==.Yourmajesty:BAAANQADCggICAAAAA==.',
['Yå']='Yåmatohime:BAAANQADCgUJBQABNQAECggIEQAYAAAAAA==.',
Za='Zada:BAAANQADCgQIBAAAAA==.Zah:BAAANQAECgUICAAAAA==.Zanntrhay:BAAANQABCgIIAgAAAA==.Zappymczaps:BAAANQADCggICgAAAA==.Zappÿ:BAAANQAECgIIAgAAAA==.Zaremis:BAABNQAECn8zAAMEAAkK6yStAwCuAwAEAAkK6yStAwCuAwAVAAMKGgPZBgF3AAAAAA==.Zayehuo:BAAANQAECgUICgAAAA==.',
Ze='Zeeni:BAABNQAECn8YAAICAAYK2A+QvgCBAQACAAYK2A+QvgCBAQAAAA==.Zelphie:BAABNQAECn8jAAICAAgKdBM+ZQBIAgACAAgKdBM+ZQBIAgAAAA==.Zemmy:BAABNQAECn8aAAIKAAcKzA2VTQB4AQAKAAcKzA2VTQB4AQAAAA==.Zemtor:BAAANQADCgYIBgAAAA==.Zent:BAAANQAECgEIAQAAAA==.Zenus:BAAANQAECgIIBAAAAA==.Zenveyra:BAAANQAECgQIBQAAAA==.Zerase:BAABNQAECn8eAAQGAAgKnBsxPQByAgAGAAgKnBsxPQByAgAHAAQKLQjHVQCxAAAIAAIK0gRuIgBRAAAAAA==.Zerttrak:BAABNQAECn8yAAMCAAkKiSLGDQBxAwACAAkKiSLGDQBxAwAXAAEKORnufgBDAAAAAA==.Zeus:BAAANQADCgQIBAAAAA==.',
Zi='Zilong:BAAANQAECgMIAwAAAA==.Zitania:BAABNQAECn8cAAIGAAcK0gxxiQB1AQAGAAcK0gxxiQB1AQAAAA==.Zivallia:BAAANQADCggICgAAAA==.',
Zu='Zugma:BAABNQAECn8fAAIcAAgKIyASXQByAgAcAAgKIyASXQByAgAAAA==.',
['Æl']='Ælin:BAAANQAECgUIDgAAAA==.',
['Çh']='Çhristopher:BAAANQADCgYICgAAAA==.',
['ßo']='ßorgrash:BAAANQADCgEIAQAAAA==.',
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
