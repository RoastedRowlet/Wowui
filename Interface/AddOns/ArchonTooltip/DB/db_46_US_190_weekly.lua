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

local lookup = {'Mage-Arcane','Unknown-Unknown','Paladin-Retribution','Priest-Discipline','Evoker-Augmentation','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','DeathKnight-Unholy','Priest-Holy','Druid-Balance','Hunter-BeastMastery','Shaman-Restoration','DeathKnight-Blood','Monk-Mistweaver','Mage-Frost','Shaman-Enhancement','Warrior-Arms','Druid-Guardian','Hunter-Marksmanship','DeathKnight-Frost','Warlock-Demonology','Warlock-Affliction','Evoker-Devastation','Warrior-Fury','Monk-Windwalker','DemonHunter-Havoc','Shaman-Elemental','Hunter-Survival','Warrior-Protection','Druid-Restoration','Paladin-Holy','DemonHunter-Devourer','Warlock-Destruction','Evoker-Preservation','Monk-Brewmaster','Paladin-Protection','Druid-Feral','DemonHunter-Vengeance','Rogue-Outlaw',}
local provider = {region='US',realm='Shadowsong',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abbinormal:BAAALgADCgUJBAAAAA==.Abysma:BAAALgAECgEJAQAAAA==.',
Ad='Adoran:BAAALgADCgEJAQAAAA==.Adorian:BAAALgAECgEJAgAAAA==.Adrenaleen:BAAALgAECgUJCQAAAA==.',
Ae='Aeosi:BAAALgADCgEJAQAAAA==.Aeriss:BAAALgADCgUJCAAAAA==.Aertin:BAAALgADCgQJBAABLgAECggJJQABAOQYAA==.Aeryhn:BAAALgADCgcJDAABLgAECgcJEAACAAAAAA==.Aezili:BAAALgAECgUJEAAAAA==.',
Af='Afkatie:BAAALgAECgQJCwAAAA==.',
Ag='Agaruu:BAAALgAECgYJBgAAAA==.Agerol:BAABLgAECn8xAAIDAAgJzCLYFACxAgADAAgJzCLYFACxAgAAAA==.Agnin:BAAALgADCgcJDgAAAA==.',
Ak='Akafabu:BAAALgAECgQJDAABLgAFFAUJFwAEAAUNAA==.Akumunter:BAAALgAECgcJEgAAAA==.Akuryujin:BAABLgAECn8pAAIFAAkJEA9EJQCZAQAFAAkJEA9EJQCZAQAAAA==.Akätsuki:BAACLgAFFH8DAAIGAAMJuAm7JADWAAAGAAMJuAm7JADWAAAuAAQKfyUAAgYACQleFJsQABACAAYACQleFJsQABACAAAA.',
Al='Alacardias:BAABLgAECn8gAAIDAAgJ1h0RNwAMAgADAAgJ1h0RNwAMAgAAAA==.Alackoflust:BAAALgAECgEJAgABLgAECgQJCwACAAAAAA==.Aladistra:BAAALgADCgMJAwAAAA==.Albert:BAAALgADCgIJAgAAAA==.Alcaedra:BAAALgADCggJCAAAAA==.Alcapwnz:BAAALgADCgYJCQAAAA==.Alinoda:BAAALgADCgIJAgAAAA==.Alleril:BAABLgAECn9JAAMGAAkJthQUEQALAgAGAAkJzRMUEQALAgAHAAgJKw/aBwDeAQAAAA==.Alley:BAAALgADCgUJCgAAAA==.Alpha:BAAALgAECgIJAgAAAA==.',
Am='Amäri:BAACLgAFFH8XAAMEAAUJBQ0yGwBHAQAEAAUJBQ0yGwBHAQAIAAUJaBEoFwAaAQAuAAQKfy8AAgQACQmuFSgSACQCAAQACQmuFSgSACQCAAAA.',
An='Anassand:BAABLgAECn8lAAIJAAkJSyO6EgDGAgAJAAkJSyO6EgDGAgAAAA==.Anatomic:BAAALgAECgMJAwABLgAECggJHgAKAFUNAA==.Andimorph:BAABLgAECn8YAAILAAgJmRy5DwBNAgALAAgJmRy5DwBNAgAAAA==.Anema:BAAALgADCgQJBAABLgAECgMJBgACAAAAAA==.Angeleria:BAABLgAECn8dAAIMAAkJOSAzEQCyAgAMAAkJOSAzEQCyAgAAAA==.Antebellum:BAAALgAECgcJBQAAAA==.',
Aq='Aqiqi:BAAALgAECgQJCwAAAA==.Aquashade:BAAALgAECgcJEQABLgAFFAUJCQANALcKAA==.Aquaterra:BAACLgAFFH8JAAINAAUJtwqMJAAxAQANAAUJtwqMJAAxAQAuAAQKfzkAAg0ACQk1JHAEAFsDAA0ACQk1JHAEAFsDAAAA.Aquina:BAAALgAECgcJEAABLgAFFAUJCQANALcKAA==.',
Ar='Arakadia:BAABLgAECn85AAMJAAkJMBYkNAAaAgAJAAkJJxQkNAAaAgAOAAUJBhMbLADfAAAAAA==.Aravena:BAAALgADCgcJAwAAAA==.Archetyepe:BAAALgAECgIJBQAAAA==.Arfus:BAAALgAECgQJBAAAAA==.Arisana:BAAALgAECgQJBwAAAA==.Aruteeru:BAABLgAECn8cAAIPAAgJlR6wDQChAgAPAAgJlR6wDQChAgAAAA==.',
As='Asathen:BAAALgADCgEJAQAAAA==.Aseanna:BAAALgAECgcJEQAAAA==.Ashadala:BAAALgAECgYJBwAAAA==.Astallivan:BAAALgADCgkJFQAAAA==.Astrevia:BAAALgAECgYJBgAAAA==.',
Au='Augabeks:BAACLgAFFH8OAAIFAAQJBBHxKQD+AAAFAAQJBBHxKQD+AAAuAAQKfyMAAgUACAmpFaEZAAACAAUACAmpFaEZAAACAAEuAAMKBwkHAAIAAAAA.Auralada:BAABLgAECn8lAAMBAAgJ5Bh/BAACAgABAAcJcht/BAACAgAQAAgJ4hIjgwBWAQAAAA==.Auxhunt:BAAALgADCgkJDQAAAA==.Auxiliator:BAAALgADCgYJCgABLgADCggJCgACAAAAAA==.',
Av='Avarous:BAAALgAECggJCAAAAA==.Avataroffury:BAAALgAECggJEQABLgAECgkJJQAJAEsjAA==.',
Ay='Ayala:BAABLgAFFH8XAAIDAAYJbyFABgApAgADAAYJbyFABgApAgAAAA==.Ayessa:BAAALgAECgYJEwABLgAFFAEJAQACAAAAAA==.',
Az='Azaireos:BAAALgAECgMJAwAAAA==.Azulpunkt:BAABLgAECn8tAAIRAAgJyR4zBwBCAgARAAgJyR4zBwBCAgAAAA==.Azzapp:BAABLgAECn8jAAISAAYJsxKKJQAkAQASAAYJsxKKJQAkAQAAAA==.',
Ba='Baddaboomkin:BAABLgAECn8eAAMLAAgJEBZEGQDpAQALAAgJEBZEGQDpAQATAAUJ0wHSVwBBAAAAAA==.Bakreingol:BAAALgAECgEJAQABLgAECgcJCwACAAAAAA==.Bammboom:BAAALgAECgEJAQAAAA==.Barbedwire:BAAALgAECgcJBAAAAA==.Baree:BAAALgAECgMJBAAAAA==.',
Be='Bearmao:BAABLgAECn87AAMMAAgJ9hnzJgAuAgAMAAgJ9hnzJgAuAgAUAAcJaQx8QQBTAQAAAA==.Bearserk:BAAALgAECgMJBwAAAA==.Beastknight:BAAALgAECgYJDgAAAA==.Beastrunner:BAAALgADCgkJEQABLgAECgYJDgACAAAAAA==.Beknight:BAACLgAFFH8HAAMOAAQJ8gRDJwCGAAAOAAQJ8gRDJwCGAAAJAAEJxwU28QA7AAAuAAQKfxYABAkABwnrEj+0APgAAAkABgnwEz+0APgAAA4AAwnkCJdKAE0AABUAAQnNFRUWADkAAAEuAAMKBwkHAAIAAAAA.Belbebbium:BAAALgAECgIJAgABLgAECggJNgALADQaAA==.Belfas:BAABLgAECn8bAAIRAAgJGhukCQAIAgARAAgJGhukCQAIAgAAAA==.Bellybutton:BAAALgAFFAEJAQAAAA==.Benafflok:BAACLgAFFH8PAAMWAAQJUxv0PgA1AQAWAAQJUxv0PgA1AQAXAAEJRAt9BgBRAAAuAAQKfyYAAxcACAk1JHYDAGMCABYACAkBJAwVAJoCABcABwn9H3YDAGMCAAEuAAEKCAkIAAIAAAAA.Bertu:BAAALgADCgEJAQAAAA==.',
Bi='Bigblight:BAAALgADCgEJAwAAAA==.Bigduck:BAAALgAECgUJCgAAAA==.Biggayjohn:BAAALgAECgYJEgAAAA==.Bigknighter:BAAALgAECgYJDgAAAA==.',
Bl='Blackclover:BAACLgAFFH8PAAINAAQJNxaDKwASAQANAAQJNxaDKwASAQAuAAQKfysAAg0ACQlIG6UeAD8CAA0ACQlIG6UeAD8CAAAA.Blackpink:BAAALgADCggJEwAAAA==.Blandicus:BAAALgADCgcJBwAAAA==.',
Bo='Boppaheks:BAAALgADCgcJBwAAAA==.Bowless:BAAALgAECgcJCAABLgAECgkJIAAWADodAA==.',
Br='Brawnstone:BAAALgAECgEJAQAAAA==.Brewsleroy:BAAALgADCgcJDQABLgADCggJCAACAAAAAA==.Brewtypoppin:BAAALgADCgQJBAAAAA==.Brey:BAAALgAECgEJAQAAAA==.Brightshield:BAAALgAECgUJBwAAAA==.Brohomir:BAAALgAECgEJAQAAAA==.Bronze:BAABLgAECn8gAAIPAAcJTA7IRgAcAQAPAAcJTA7IRgAcAQAAAA==.Brunee:BAABLgAECn8WAAIIAAgJzwpMJwCeAQAIAAgJzwpMJwCeAQAAAA==.Bruute:BAACLgAFFH8FAAISAAIJqCONHwDLAAASAAIJqCONHwDLAAAuAAQKfzgAAhIACAkiJRkDAPACABIACAkiJRkDAPACAAAA.',
Bu='Budplatinum:BAABLgAECn8iAAIYAAgJ/woGCwBUAQAYAAgJ/woGCwBUAQAAAA==.Buffbuffheal:BAAALgAECgMJAwABLgAECgYJCgACAAAAAA==.Buhemoth:BAAALgAECgcJDgAAAA==.Bumi:BAAALgADCgQJBAAAAA==.Butters:BAAALgAECgIJAgAAAA==.',
['Bâ']='Bâït:BAAALgAECgYJCwABLgAECgcJBwACAAAAAA==.',
['Bã']='Bãìt:BAAALgAECgUJBQABLgAECgcJBwACAAAAAA==.',
['Bä']='Bäït:BAAALgAECgcJAQABLgAECgcJBwACAAAAAA==.',
Ca='Caemaris:BAAALgADCgQJBAAAAA==.Cairo:BAABLgAECn8XAAIZAAgJrhhLIwA7AgAZAAgJrhhLIwA7AgAAAA==.Cakes:BAABLgAECn8aAAIKAAYJJBWyMQAtAQAKAAYJJBWyMQAtAQAAAA==.Calai:BAAALgADCgkJEwAAAA==.Canadiian:BAAALgAECgYJDwAAAA==.Capitalchaos:BAABLgAECn82AAIZAAgJpRzrFwAaAgAZAAgJpRzrFwAaAgABLgAFFAIJAgACAAAAAA==.Cassandraa:BAAALgAECgQJBAAAAA==.',
Ce='Cearrdorn:BAAALgAECgUJCgABLgAECggJNwADABMjAA==.Cearreotadh:BAAALgADCgQJBAAAAA==.Celticrock:BAAALgAECgEJAgAAAA==.Ceviche:BAACLgAFFH8QAAIaAAUJTholDgA4AQAaAAUJTholDgA4AQAuAAQKfx4AAhoACQmhIrgFACgDABoACQmhIrgFACgDAAAA.Ceàrrdòrn:BAABLgAECn83AAIDAAgJEyOCJABaAgADAAgJEyOCJABaAgAAAA==.',
Ch='Chaskitty:BAAALgAECgIJAgAAAA==.Cheetahgirl:BAAALgAECgEJBQAAAA==.Chickenjoy:BAAALgADCgcJBwAAAA==.Chillzmatic:BAACLgAFFH8JAAIbAAQJoAsUEAAAAQAbAAQJoAsUEAAAAQAuAAQKfxwAAhsABgnHI5wYAAICABsABgnHI5wYAAICAAAA.Chirri:BAAALgAECgQJCwAAAA==.Chondriac:BAABLgAECn8gAAIcAAgJ0xp5FwAQAgAcAAgJ0xp5FwAQAgAAAA==.Chow:BAAALgADCgQJBAAAAA==.Chrisdirect:BAAALgADCgQJBAAAAA==.Chudbucket:BAABLgAECn8pAAMdAAcJLR6uEwD9AQAdAAcJLR6uEwD9AQAUAAYJ1BdkPABtAQAAAA==.Chàssy:BAAALgAECgIJAwAAAA==.',
Ci='Cilantro:BAAALgADCgEJAQABLgAECgcJEQACAAAAAA==.Cinabun:BAAALgADCgIJAgAAAA==.Cirillø:BAABLgAECn8aAAIeAAkJVh2GCQBHAgAeAAkJVh2GCQBHAgAAAA==.',
Cl='Clinictrials:BAAALgAECggJEQAAAA==.Cloverblack:BAAALgADCgEJAQAAAA==.',
Co='Corbis:BAABLgAECn8cAAMfAAcJEglqYwD5AAAfAAcJEglqYwD5AAALAAIJhQZHgQAvAAAAAA==.Covidmage:BAAALgADCgUJCgAAAA==.Cowpatty:BAAALgADCgYJFQAAAA==.',
Cr='Crepitate:BAAALgAECgEJAQABLgAECgcJBwACAAAAAA==.Crunchwich:BAAALgAECgcJEgAAAA==.',
Cu='Cuchi:BAAALgADCgkJDAAAAA==.Cutename:BAABLgAECn8WAAIMAAYJOQTlpwDTAAAMAAYJOQTlpwDTAAAAAA==.',
Cy='Cynamyn:BAAALgAECgcJEgAAAA==.Cyraea:BAAALgAECgMJCQAAAA==.',
Cz='Czeskilight:BAABLgAECn8iAAIEAAkJORHQGgDXAQAEAAkJORHQGgDXAQAAAA==.',
['Câ']='Câl:BAAALgAECgEJAQAAAA==.',
['Cå']='Cåle:BAAALgAECgUJDQAAAA==.',
['Cè']='Cèrol:BAAALgAECgEJAQAAAA==.',
Da='Daane:BAAALgAECgMJAwAAAA==.Dabadwarrior:BAABLgAECn8+AAMZAAgJFRkEIgDOAQAZAAgJihgEIgDOAQAeAAcJyQ8VHgApAQAAAA==.Dabs:BAAALgAECgEJAQAAAA==.Dabzilla:BAAALgAECgQJBAABLgAECggJHQAgAJgbAA==.Dabzîlla:BAAALgADCggJDAABLgAECggJHQAgAJgbAA==.Daffadill:BAAALgADCgEJAQAAAA==.Dakhran:BAAALgADCgUJFAAAAA==.Dan:BAAALgAECgcJDwAAAA==.Danero:BAAALgAECgEJAQAAAA==.Darkchangu:BAAALgAECgYJCQAAAA==.Darkdemon:BAABLgAECn8uAAIhAAkJiRHaOADMAQAhAAkJiRHaOADMAQAAAA==.Darknessz:BAAALgADCgkJDwAAAA==.Darkovia:BAAALgADCgMJAwAAAA==.Darksecrets:BAAALgAECgIJAQAAAA==.Darkshyne:BAAALgADCgcJBwAAAA==.Darlord:BAAALgAECgcJEgAAAA==.',
De='Deagle:BAACLgAFFH8SAAIGAAQJHR9NDgB2AQAGAAQJHR9NDgB2AQAuAAQKf0EAAgYACAn7JQ4EAOwCAAYACAn7JQ4EAOwCAAAA.Deathpunkt:BAAALgAECgQJCQAAAA==.Deedubbya:BAAALgADCgMJAwAAAA==.Defense:BAAALgADCgkJIQAAAA==.Delryd:BAAALgAECgcJEgAAAA==.Demonfrog:BAACLgAFFH8QAAIJAAQJVA98XAAiAQAJAAQJVA98XAAiAQAuAAQKfygAAgkACQlkF7BJANMBAAkACQlkF7BJANMBAAAA.Demônlock:BAAALgAECgcJEgAAAA==.Desideria:BAABLgAECn8tAAIWAAgJIAYWhQAlAQAWAAgJIAYWhQAlAQAAAA==.Desynn:BAABLgAECn80AAIWAAgJ+hfUMQAEAgAWAAgJ+hfUMQAEAgAAAA==.Dethtouch:BAAALgAECgIJAgAAAA==.Deyndel:BAABLgAECn8WAAIDAAYJDgbvvwAHAQADAAYJDgbvvwAHAQAAAA==.',
Di='Divinesyn:BAABLgAECn8UAAIKAAkJxAz+JQB/AQAKAAkJxAz+JQB/AQAAAA==.',
Dj='Djtaki:BAACLgAFFH8JAAIGAAMJWBQIIQDxAAAGAAMJWBQIIQDxAAAuAAQKfyMAAwYABwkiF9McABgCAAYABwkiF9McABgCAAcAAQlcD/0jADQAAAAA.',
Do='Dobs:BAABLgAECn8kAAITAAkJ/BlNCQA1AgATAAkJ/BlNCQA1AgAAAA==.Dogwater:BAACLgAFFH8IAAIdAAYJRA9rCQBsAQAdAAYJRA9rCQBsAQAuAAQKfy4AAx0ACAlLIY8EANACAB0ACAlLIY8EANACABQAAQk5DIGMAC8AAAAA.Domimpatrix:BAAALgADCgYJBgAAAA==.Doncarlos:BAABLgAECn8lAAIMAAgJSSJwEQCwAgAMAAgJSSJwEQCwAgAAAA==.Dopey:BAAALgAECgMJBgAAAA==.Dorn:BAAALgADCgQJBAAAAA==.Dotsonly:BAABLgAECn8WAAMXAAgJYBKUDgBRAQAXAAYJ0RSUDgBRAQAWAAYJCBBUugDHAAAAAA==.Dotty:BAAALgAECgIJBAAAAA==.Downbeatxo:BAECLgAFFH8aAAMWAAgJaRWCCQApAgAWAAgJaRWCCQApAgAiAAEJSBXWFABVAAAuAAQKfy0AAxYACQknJDsLACEDABYACQknJDsLACEDACIAAgnUHDROAIMAAAAA.',
Dr='Dracow:BAAALgADCgkJFAABLgAECggJJgAhAHkZAA==.Drippie:BAAALgADCgUJBwAAAA==.Droodormi:BAAALgAECgIJAgAAAA==.',
Du='Dubdred:BAAALgAECgMJCAABLgAECggJLQAgANcYAA==.Duberrok:BAABLgAECn8tAAMgAAgJ1xgBGgAfAgAgAAgJ1xgBGgAfAgADAAMJxQ1N+wCdAAAAAA==.Dumptruck:BAAALgAECgEJAQAAAA==.Dunes:BAAALgAECgQJBAAAAA==.Dunidane:BAAALgADCgYJBgAAAA==.Durk:BAAALgAECgUJCQAAAA==.Durkk:BAAALgAECgUJBQAAAA==.',
Dw='Dwarfskin:BAAALgADCgQJBQAAAA==.Dwín:BAABLgAECn8jAAMMAAkJRQYhcABIAQAMAAkJRQYhcABIAQAUAAEJ+QCPmgAYAAAAAA==.',
Ea='Earthstalker:BAABLgAECn8WAAINAAgJECWIBQBGAwANAAgJECWIBQBGAwAAAA==.',
El='Elasper:BAAALgAECgUJEQAAAA==.Eleathis:BAAALgAECgMJBAAAAA==.',
Em='Emelianas:BAAALgADCgkJCQAAAA==.Emotionalism:BAAALgAECgYJBgAAAA==.Emäcs:BAAALgADCgIJAgAAAA==.',
En='Endimion:BAAALgADCgQJBAAAAA==.Enjin:BAABLgAECn8uAAMdAAkJxiBGCACNAgAdAAkJxiBGCACNAgAMAAEJVgSzHgEuAAAAAA==.Enragedbeef:BAABLgAECn8ZAAMDAAYJhBLAjABiAQADAAYJhBLAjABiAQAgAAQJ1g05awDNAAABLgAFFAQJCAAWAAMHAA==.Entheogen:BAABLgAECn8ZAAIcAAgJLxrxFwAMAgAcAAgJLxrxFwAMAgAAAA==.',
Ep='Eps:BAAALgADCgUJBQAAAA==.',
Er='Erahlon:BAAALgADCgkJHQAAAA==.Eralak:BAAALgADCgIJAgAAAA==.Ereckshaun:BAAALgADCgQJAgAAAA==.Eree:BAAALgAECgMJBQAAAA==.Eremin:BAAALgADCgUJBQAAAA==.Erinora:BAAALgAECgEJAQABLgAFFAYJEQAIABUVAA==.Ermoonsia:BAAALgADCgcJDAAAAA==.Erolas:BAAALgAECgQJBAAAAA==.',
Ev='Evanessance:BAAALgADCggJFQAAAA==.Evoka:BAABLgAECn8ZAAIjAAgJnQboGQAkAQAjAAgJnQboGQAkAQAAAA==.Evopunkt:BAAALgAECgcJDAAAAA==.',
Fa='Faavimonk:BAABLgAECn8XAAMaAAYJ3RZbMQBgAQAaAAYJgRNbMQBgAQAkAAEJhx9/cABVAAAAAA==.Fallendevout:BAAALgADCgkJFgAAAA==.Fallendots:BAAALgADCgUJCQAAAA==.Fallenseer:BAABLgAECn8XAAIcAAYJbBo2OwBhAQAcAAYJbBo2OwBhAQAAAA==.Fallentroll:BAACLgAFFH8OAAIJAAQJdgyDZwAQAQAJAAQJdgyDZwAQAQAuAAQKfxkAAgkACAmFFoNRALwBAAkACAmFFoNRALwBAAAA.Faress:BAAALgAECgEJAgAAAA==.Fatdoinkers:BAAALgAECgEJAQAAAA==.Fatman:BAAALgAECgcJEQAAAA==.Faydark:BAABLgAECn8VAAMXAAUJSxbnEgAZAQAXAAUJSxbnEgAZAQAWAAQJLgtG1ACbAAAAAA==.Fayia:BAAALgAECgUJCQAAAA==.Fayye:BAABLgAECn8eAAIgAAgJ7g6ZLACYAQAgAAgJ7g6ZLACYAQAAAA==.',
Fe='Feliandril:BAAALgAECgEJAQAAAA==.Fellin:BAABLgAECn8vAAMMAAkJKwkqUACZAQAMAAkJawgqUACZAQAUAAgJ2AWmFAABAQAAAA==.Femto:BAACLgAFFH8SAAIJAAMJPSXzIAAVAQAJAAMJPSXzIAAVAQAuAAQKf0EAAgkACQkZJYgFAEMDAAkACQkZJYgFAEMDAAAA.',
Fi='Fiestyrae:BAAALgAECgEJAgAAAA==.Fintrollz:BAAALgAECgYJCwAAAA==.Fiorina:BAAALgAECgEJAQABLgAECggJNgALADQaAA==.Fireburd:BAAALgADCgYJCgAAAA==.Firèflyjd:BAABLgAECn8iAAQXAAgJzCB7BQASAgAXAAYJ6R97BQASAgAWAAYJEB8PMwD/AQAiAAQJBh6WHACuAAAAAA==.Fishersam:BAAALgADCgYJBgAAAA==.Fishy:BAAALgADCgkJDwAAAA==.',
Fl='Flintzombie:BAAALgADCgkJCgABLgAECggJNAAeAEoYAA==.Floatpass:BAACLgAFFH8PAAIQAAQJ2hSPSgA5AQAQAAQJ2hSPSgA5AQAuAAQKfy8AAhAACAkzIa8hAIECABAACAkzIa8hAIECAAAA.Floweranjel:BAAALgADCgYJEAAAAA==.Fluffymyone:BAABLgAECn8xAAIQAAgJnAL4zQDVAAAQAAgJnAL4zQDVAAAAAA==.',
Fo='Foghat:BAAALgADCgcJCgAAAA==.Fongsiyuk:BAABLgAECn8XAAIaAAYJRBFVPAD2AAAaAAYJRBFVPAD2AAAAAA==.Foxhammer:BAAALgADCgkJEAAAAA==.',
Fr='Fredwick:BAAALgADCgUJBQABLgAECgQJBAACAAAAAA==.Freezeberry:BAAALgAECgEJAwAAAA==.Friede:BAACLgAFFH8GAAIQAAIJRg0KjwCTAAAQAAIJRg0KjwCTAAAuAAQKfxYAAhAACQkGF0ozADMCABAACQkGF0ozADMCAAEuAAUUAwkSAAkAPSUA.Frizz:BAAALgAECgcJDQAAAA==.Froey:BAAALgADCgQJBAAAAA==.Froeyglaive:BAAALgAECgQJCAAAAA==.Frostednipps:BAAALgADCggJCAAAAA==.',
Fu='Funeemonkee:BAAALgAECgIJAgABLgAECgkJMQAJAAUhAA==.Furlog:BAAALgADCgYJBwAAAA==.Fuzz:BAAALgADCgIJAgAAAA==.Fuzzymonk:BAAALgAECgcJDAAAAA==.Fuzzynuttz:BAAALgAECgkJBwAAAA==.Fuzzytotems:BAABLgAFFH8OAAINAAUJdBliGAB2AQANAAUJdBliGAB2AQAAAA==.',
['Fá']='Fáavi:BAAALgAECgUJBQABLgAECgkJFwAaAN0WAA==.',
Ga='Gabagooly:BAAALgAECgMJAwAAAA==.Gali:BAACLgAFFH8NAAMMAAQJWBDsDQDoAAAMAAQJNw/sDQDoAAAUAAMJNgZwHgCEAAAuAAQKfzQABAwACQmaG3IOAMgCAAwACQmHG3IOAMgCABQACAlbFB86AHkBAB0AAQkCFoFWAD8AAAAA.Galiagante:BAAALgADCgcJFgAAAA==.Galiashammy:BAAALgADCgUJBQABLgADCgcJFgACAAAAAA==.Gallynna:BAABLgAECn88AAQXAAkJ6hmNBAAvAgAXAAgJGRuNBAAvAgAWAAYJyBFAaABhAQAiAAYJFRGnNADkAAAAAA==.Galorfax:BAABLgAECn81AAITAAgJcx8ABwBsAgATAAgJcx8ABwBsAgAAAA==.Galorfox:BAAALgADCgUJBQAAAA==.Galushi:BAAALgAECgQJBAAAAA==.Gamervato:BAAALgAECgIJAgAAAA==.Gannondalf:BAAALgADCgUJBQABLgAECggJNAAeAEoYAA==.Garlic:BAAALgAECgMJBgAAAA==.Garm:BAABLgAECn8iAAIMAAcJzCEoJwAsAgAMAAcJzCEoJwAsAgAAAA==.',
Ge='Gelinea:BAAALgAECgcJEgAAAA==.Genovese:BAABLgAECn8ZAAMJAAkJ8gk5kgAtAQAJAAgJnwk5kgAtAQAVAAcJTgk1HgCoAAAAAA==.Gerardbutler:BAAALgADCgkJCQAAAA==.Geyboy:BAAALgAECgUJCAAAAA==.',
Gi='Gilagain:BAAALgAECgIJAgAAAA==.Gilgameshx:BAAALgADCgIJAgAAAA==.Gilgaroth:BAABLgAECn8mAAMGAAgJExwqFwDLAQAGAAcJgx8qFwDLAQAHAAMJoA1SFwCiAAAAAA==.Girdlin:BAAALgADCgcJEgAAAA==.Girlslove:BAABLgAECn8VAAMFAAkJuB9gCAC7AgAFAAkJ9B5gCAC7AgAYAAEJGCWzGQBuAAABLgAFFAYJCAAdAEQPAA==.',
Gl='Glaucoma:BAABLgAECn8WAAIhAAgJ0BSHQgCpAQAhAAgJ0BSHQgCpAQAAAA==.',
Go='Gobo:BAAALgAECgMJAwABLgAECgkJIQAFAHMSAA==.Goochpooch:BAAALgAECgUJBwAAAA==.Gorendish:BAAALgAECgUJBQAAAA==.Gotideath:BAAALgAECgYJCwABLgAECgkJLwAaAPcbAA==.Goude:BAAALgADCgkJCQAAAA==.',
Gr='Graevus:BAACLgAFFH8FAAIfAAMJHBcYMgDYAAAfAAMJHBcYMgDYAAAuAAQKfzEAAx8ACQnaFikhADsCAB8ACQnaFikhADsCAAsABwkwEMQwAD8BAAAA.Graku:BAAALgAECgkJEQAAAA==.Graysonn:BAAALgAECgEJAQAAAA==.Greyheart:BAAALgADCgUJBQAAAA==.Grimmora:BAAALgADCgYJDwAAAA==.Grëybeard:BAACLgAFFH8IAAISAAMJUQ7+HgDOAAASAAMJUQ7+HgDOAAAuAAQKfz0AAhIACQlPH5EDANwCABIACQlPH5EDANwCAAAA.Grýla:BAAALgAECgcJBwAAAA==.',
Gu='Gundrakk:BAACLgAFFH8RAAIfAAQJMhLrJwAKAQAfAAQJMhLrJwAKAQAuAAQKfz8AAx8ACQn/IjcDAIYDAB8ACQn/IjcDAIYDAAsACAnYDBIuAE8BAAAA.Gunnr:BAAALgAECgQJBAABLgAFFAEJAQACAAAAAA==.Gunthorian:BAABLgAECn9BAAQlAAkJmhsLCgARAgAlAAgJ2hsLCgARAgADAAkJCxEuUAC/AQAgAAYJgBHmTABFAQAAAA==.Gurusham:BAAALgAECgEJAwAAAA==.',
Ha='Hame:BAAALgADCgMJAwAAAA==.Hamme:BAAALgADCgEJAQAAAA==.Handsomemonk:BAABLgAECn8rAAQPAAgJBRlCIQDpAQAPAAcJCBpCIQDpAQAkAAcJPxTrSQAbAQAaAAUJuRC8ZgBrAAAAAA==.Hangvhul:BAABLgAECn8hAAIRAAkJ0Q4nEACQAQARAAkJ0Q4nEACQAQAAAA==.Hansi:BAABLgAFFH8FAAIfAAIJ9w1ZTAB5AAAfAAIJ9w1ZTAB5AAAAAA==.Harkonnen:BAABLgAECn85AAQWAAgJvg9KXwB3AQAWAAgJYQ9KXwB3AQAiAAEJ+RO4cQA0AAAXAAEJ8gW3OQArAAAAAA==.',
He='Healmme:BAAALgAECgUJBQAAAA==.Heart:BAAALgAECgMJCAABLgAECgQJCwACAAAAAA==.Hearth:BAAALgAECgEJAQAAAA==.Hectic:BAAALgADCgMJAwABLgAECggJHQAgAJgbAA==.Heid:BAAALgAECgQJBAAAAA==.Helianna:BAAALgAFFAMJAwABLgAFFAcJGQAMAHMaAA==.Helldozer:BAAALgAECgUJEAAAAA==.Hellsong:BAAALgADCgUJBQAAAA==.',
Hi='Himejoshi:BAACLgAFFH8JAAImAAQJsSCsAwBlAQAmAAQJsSCsAwBlAQAuAAQKfyMAAyYACAmOJGUBAFwDACYACAmOJGUBAFwDABMABwnsHuIFAHUCAAEuAAUUBgkIAB0ARA8A.Hirys:BAACLgAFFH8MAAIGAAMJ/xrvHQAIAQAGAAMJ/xrvHQAIAQAuAAQKfxoAAgYACQkgHooMAEYCAAYACQkgHooMAEYCAAAA.',
Ho='Holybanana:BAABLgAECn8hAAIgAAgJsyKSCQDeAgAgAAgJsyKSCQDeAgAAAA==.Holymerble:BAAALgAECgEJAQABLgAECgcJDwACAAAAAA==.Holyramen:BAAALgADCgcJBwAAAA==.Horsewing:BAAALgAECgYJEAAAAA==.Hotdoggin:BAAALgAECgYJCAAAAA==.Hotmerble:BAAALgAECgcJDwAAAA==.Hotshotzz:BAAALgAECgQJBgABLgAFFAYJEAAQAD8PAA==.Hotstreak:BAACLgAFFH8QAAIQAAYJPw/jMAB7AQAQAAYJPw/jMAB7AQAuAAQKfx4AAhAACQk7HcEaAKQCABAACQk7HcEaAKQCAAAA.',
Hu='Hunthamme:BAAALgAECgYJDQAAAA==.Huntsmedown:BAAALgAECgMJBQAAAA==.',
Hy='Hyjali:BAAALgADCgEJAQAAAA==.',
['Há']='Háldrin:BAACLgAFFH8ZAAQMAAcJcxplIgBVAQAMAAYJKxBlIgBVAQAdAAUJcBcCDwBDAQAUAAMJHhVbIQBoAAAuAAQKfyAABBQACAkpHFccAEUCABQACAkCGlccAEUCAB0ABglWIVQWAOMBAAwABAnUIrt4ADUBAAAA.',
['Hä']='Härmacist:BAAALgAECgUJBQAAAA==.',
Ia='Iamcow:BAAALgAECgUJCQAAAA==.',
Il='Illexi:BAAALgADCgYJBgAAAA==.Ilthunis:BAAALgADCgcJEAAAAA==.',
Im='Imadruîd:BAAALgAECgYJCgAAAA==.Imbue:BAABLgAECn8kAAInAAkJCB7jBABMAgAnAAkJCB7jBABMAgAAAA==.Immortals:BAAALgAECgQJBQAAAA==.Imthatguyy:BAAALgAECgMJAwABLgAECgYJDQACAAAAAA==.',
In='Innil:BAACLgAFFH8JAAMEAAQJ0BU5HgAmAQAEAAQJ0BU5HgAmAQAIAAEJ0wYwMwBBAAAuAAQKfxYABAoACQl/GtI0AGsBAAoABgmNGdI0AGsBAAgACAlJFdorAFYBAAQAAwl4EQxPAJUAAAAA.',
Ip='Ipunch:BAAALgAECgQJDAABLgAECgYJDQACAAAAAA==.',
Is='Isimiel:BAAALgADCgQJBAAAAA==.Isolda:BAAALgAECgQJBAAAAA==.',
It='Itahchii:BAAALgADCgUJBQABLgAECgQJBAACAAAAAA==.Itzapazz:BAAALgADCgkJDQAAAA==.',
Iv='Ivyrahh:BAAALgADCgMJAwAAAA==.',
Ja='Jaesa:BAAALgADCgEJAQAAAA==.Jardah:BAAALgAECgQJBQABLgAECgYJDQACAAAAAA==.Jaycee:BAAALgADCgcJCgAAAA==.',
Je='Jessicks:BAAALgAECgQJBQABLgAECgUJCQACAAAAAA==.Jessiks:BAAALgAECgYJBwAAAA==.Jessix:BAAALgAECgUJCQAAAA==.Jetlisa:BAAALgADCgcJBwAAAA==.Jeybi:BAAALgAFFAMJBAAAAA==.Jezebel:BAABLgAECn8sAAMWAAgJJRqOKwAeAgAWAAgJJRqOKwAeAgAiAAEJmARtPQAmAAAAAA==.',
Ji='Jiaoe:BAAALgADCgQJBAAAAA==.Jimfowler:BAAALgADCgEJAQAAAA==.Jinxing:BAAALgAECgMJAwAAAA==.Jinze:BAAALgAECgQJBgAAAA==.Jirito:BAAALgADCgcJBwABLgAECgkJGgAfALQNAA==.Jirto:BAABLgAECn8aAAIfAAkJtA3YSAB/AQAfAAkJtA3YSAB/AQAAAA==.',
Jo='Jomadead:BAABLgAECn8oAAIOAAkJLByBCgBRAgAOAAkJLByBCgBRAgABLgAFFAcJJQANAF0YAA==.Jomadh:BAABLgAFFH8GAAIhAAUJtwnSRgD5AAAhAAUJtwnSRgD5AAAAAA==.Jomadin:BAAALgAECgEJAQABLgAFFAcJJQANAF0YAA==.Jomage:BAAALgAECgMJAwABLgAFFAcJJQANAF0YAA==.Jomar:BAAALgAECgcJDgAAAA==.Jomas:BAACLgAFFH8lAAMNAAcJXRijBABHAgANAAcJXRijBABHAgAcAAIJxBLCMwCYAAAuAAQKfzAAAw0ACQl2IucHAPYCAA0ACQl2IucHAPYCABwABgkLIL0xAJUBAAAA.',
Ju='Jubbjubb:BAACLgAFFH8OAAIQAAQJoQ1bXAAZAQAQAAQJoQ1bXAAZAQAuAAQKfzEAAhAACQlDIOwSANQCABAACQlDIOwSANQCAAAA.Judera:BAABLgAECn8kAAIDAAgJVBkNTADKAQADAAgJVBkNTADKAQAAAA==.Jugful:BAAALgAECgEJAQAAAA==.Juicemoose:BAABLgAECn8yAAMfAAkJMQ1eXgAJAQAfAAkJMQ1eXgAJAQALAAIJFAXIiQAnAAAAAA==.Juicybooty:BAAALgADCgUJBQAAAA==.Justokelf:BAABLgAECn8oAAIhAAgJcSGEFACLAgAhAAgJcSGEFACLAgAAAA==.',
Jw='Jwarr:BAAALgADCgEJAQAAAA==.',
Ka='Kagura:BAAALgADCgcJBwAAAA==.Kaiden:BAAALgADCgkJGwAAAA==.Kaing:BAABLgAECn8fAAMZAAYJ8w6RSwABAQAZAAYJ8w6RSwABAQAeAAEJsgunUwAdAAAAAA==.Kainlithia:BAAALgAFFAEJAgAAAA==.Kaladen:BAAALgAECgQJBwAAAA==.Kalindica:BAAALgADCgYJBgAAAA==.Kalysti:BAAALgAECggJNgAAAQ==.Kandee:BAAALgAECgYJEQAAAA==.Karkonas:BAAALgADCgcJCAABLgAFFAEJBAACAAAAAA==.Karliahdark:BAAALgAECgMJBAAAAA==.Karolg:BAAALgAECgQJBAAAAA==.Karuli:BAAALgADCgkJIgAAAA==.Karvis:BAAALgAECgUJDgAAAA==.Kasuri:BAAALgAECgEJAwAAAA==.Katostrafic:BAABLgAECn8lAAIEAAgJcR2sCgCnAgAEAAgJcR2sCgCnAgAAAA==.Katotonic:BAAALgAECgEJAQAAAA==.Kaylieè:BAAALgADCgEJAQABLgAECggJIgAXAMwgAA==.Kazemage:BAABLgAECn8lAAMBAAgJ8hTOAwC6AQABAAgJ8hTOAwC6AQAQAAEJKQJHYAEhAAAAAA==.Kazesun:BAAALgAFFAEJAQAAAA==.',
Ke='Keenora:BAAALgAECgEJAQAAAA==.Kessarian:BAAALgADCgkJCQAAAA==.Kevais:BAAALgAECgYJCAAAAA==.',
Kh='Khromscarin:BAACLgAFFH8MAAInAAMJ+CKRAwAmAQAnAAMJ+CKRAwAmAQAuAAQKfz8AAicACQkCIxgBACEDACcACQkCIxgBACEDAAAA.',
Ki='Kiaradarkpaw:BAAALgAECgEJAwAAAA==.Kielli:BAAALgADCgEJAQAAAA==.Kikianah:BAAALgAECgMJAgABLgAECggJLgAKAKQhAA==.Killboi:BAAALgAECgUJCwAAAA==.Killem:BAAALgADCgQJBAAAAA==.Killidan:BAACLgAFFH8SAAIhAAUJzBqeLgBAAQAhAAUJzBqeLgBAAQAuAAQKfxsAAiEACQlOIoURAPICACEACQlOIoURAPICAAAA.Kimberllynn:BAAALgAECgcJBwAAAA==.Kiridus:BAABLgAECn82AAMLAAgJNBreFgABAgALAAgJNBreFgABAgAfAAEJoQT54QAjAAAAAA==.Kirklees:BAAALgAECgQJCAAAAA==.',
Kl='Klaudiuss:BAAALgAECgQJBAAAAA==.',
Kn='Knackers:BAAALgADCggJDQAAAA==.',
Ko='Kodama:BAABLgAECn85AAIcAAgJ5BEvMQBgAQAcAAgJ5BEvMQBgAQAAAA==.Koi:BAAALgADCgkJEAABLgAECgkJOwAhAAElAA==.Kookiemon:BAAALgAECgYJBQAAAA==.Kookiesplz:BAAALgADCgkJHQAAAA==.Kopili:BAABLgAECn8XAAIkAAUJhAMEXwCBAAAkAAUJhAMEXwCBAAAAAA==.Koryn:BAABLgAECn8fAAIIAAcJbw+aMQA0AQAIAAcJbw+aMQA0AQAAAA==.Kotz:BAAALgAECggJEAAAAA==.',
Kr='Kratina:BAAALgADCgEJAQAAAA==.Kreshtharion:BAAALgADCgYJBgAAAA==.Krunthe:BAAALgAECgQJBAAAAA==.Kryxis:BAAALgAECgcJDgAAAA==.',
Ku='Kunpochiken:BAAALgAECgQJCQABLgAECggJJQAEAHEdAA==.',
Ky='Kyanna:BAAALgAECgcJEgAAAA==.Kyllan:BAAALgADCgIJAgAAAA==.',
La='Lacrymos:BAABLgAECn8xAAInAAkJrBoFBQBGAgAnAAkJrBoFBQBGAgAAAA==.Lader:BAAALgAECgkJEAAAAA==.Larril:BAAALgADCgYJBwAAAA==.Laurebeth:BAAALgADCgkJDQAAAA==.Laxinmedium:BAAALgAECgQJBAAAAA==.Laxinstalker:BAAALgADCgUJBQABLgAECgQJBAACAAAAAA==.',
Le='Leenei:BAAALgAECgYJCgAAAA==.Leesina:BAAALgAECgQJBwAAAA==.Lenlaar:BAAALgAECgcJEgAAAA==.Lesavatar:BAAALgADCgUJBQABLgAECgkJJQAJAEsjAA==.Levande:BAACLgAFFH8FAAIKAAMJRhRMGQDQAAAKAAMJRhRMGQDQAAAuAAQKfxwAAwoACQmYG+wSAEgCAAoACQmYG+wSAEgCAAQABQn9DZgxABQBAAAA.',
Li='Lid:BAAALgADCgMJAwAAAA==.Lifeblume:BAAALgADCgYJBgAAAA==.Lightshade:BAABLgAFFH8JAAIDAAkJJgGQgACHAAADAAkJJgGQgACHAAAAAA==.Lighttickle:BAAALgADCgMJAwAAAA==.Liling:BAAALgADCgEJAgABLgAECgYJCgACAAAAAA==.Lilithandria:BAABLgAECn8mAAMhAAgJeRkMNgDXAQAhAAgJJRgMNgDXAQAbAAQJDBnqJQAlAQAAAA==.Lilletth:BAAALgADCgUJBQAAAA==.Lilyola:BAABLgAECn8YAAIBAAYJggYmCgDGAAABAAYJggYmCgDGAAAAAA==.Limabeanjr:BAAALgADCggJCAAAAA==.Linamar:BAAALgADCgkJSwAAAA==.Lisan:BAAALgAECgQJBAAAAA==.',
Ll='Llaira:BAAALgAECgEJAQABLgAECggJFgANABAlAA==.',
Lo='Loaq:BAACLgAFFH8JAAIEAAMJJA7wKgDAAAAEAAMJJA7wKgDAAAAuAAQKfzMAAgQACQmiHdUIAK8CAAQACQmiHdUIAK8CAAAA.Lockzrockz:BAAALgAFFAIJAwAAAA==.Longbottom:BAAALgAECgYJBgAAAA==.Lorbert:BAAALgAECgQJCQABLgAECgcJIAAZAOoXAA==.',
Lu='Luxæterna:BAABLgAECn9EAAIDAAkJqBztHgB2AgADAAkJqBztHgB2AgAAAA==.',
Ly='Lystrasza:BAABLgAECn8dAAIYAAkJRRcqBQAAAgAYAAkJRRcqBQAAAgAAAA==.Lyte:BAAALgADCgYJEAAAAA==.',
['Lí']='Líllìth:BAAALgADCgYJBgAAAA==.',
Ma='Madjekyll:BAAALgAECgEJAwABLgAECggJNAAZALUlAA==.Magnamalo:BAAALgAECgcJCgABLgAFFAEJAQACAAAAAA==.Magus:BAAALgAECgIJBQAAAA==.Maikeru:BAABLgAECn8pAAIoAAcJnh/qBAASAgAoAAcJnh/qBAASAgAAAA==.Maizy:BAAALgADCgIJAgAAAA==.Malduku:BAAALgADCgYJBgAAAA==.Malemenas:BAAALgADCgkJJgAAAA==.Malice:BAABLgAECn8sAAMXAAgJEiFlAQDfAgAXAAgJEiFlAQDfAgAWAAMJRwtG2QCSAAAAAA==.Mandwandos:BAAALgAECgkJEQAAAA==.Maraliss:BAABLgAECn8kAAImAAgJXw86EwBlAQAmAAgJXw86EwBlAQAAAA==.Marjon:BAABLgAECn8jAAIiAAcJTw72EQAOAQAiAAcJTw72EQAOAQAAAA==.Maroonfive:BAAALgAECgEJAgAAAA==.Marrash:BAAALgADCgcJBgAAAA==.Masashii:BAAALgADCgkJDQABLgAECgkJOwAhAAElAA==.Mastatea:BAAALgADCggJCgAAAA==.Matamoros:BAAALgADCgcJCAAAAA==.Maugrimm:BAAALgAECgYJDQAAAA==.Maxn:BAAALgAECgEJAwAAAA==.Maxrox:BAAALgAECgQJBAAAAA==.Mayalodu:BAAALgAECgQJEQAAAA==.',
Me='Mekkanna:BAAALgAECgMJAwAAAA==.Melaunis:BAAALgAECgcJEAAAAA==.Mellwynn:BAAALgADCgkJAwAAAA==.Mellínna:BAAALgADCgYJCwAAAA==.Meora:BAAALgAECgcJCQABLgAFFAYJHgAeAMEbAA==.Meowelf:BAAALgADCgUJBQAAAA==.Meowow:BAABLgAECn8YAAIQAAcJggnZxADjAAAQAAcJggnZxADjAAAAAA==.Meowzer:BAAALgADCgEJAQABLgAFFAQJCAAWAAMHAA==.Merks:BAABLgAECn8XAAMDAAcJdAhK1QDNAAADAAcJoAZK1QDNAAAlAAQJOAoxMACMAAAAAA==.Metas:BAAALgAECgcJDQABLgAFFAYJHgAeAMEbAA==.Meteora:BAACLgAFFH8eAAIeAAYJwRuWCAB+AQAeAAYJwRuWCAB+AQAuAAQKfyMAAh4ACQmKHp8IAJYCAB4ACQmKHp8IAJYCAAAA.Metero:BAAALgAECgkJEAABLgAFFAYJHgAeAMEbAA==.',
Mh='Mhithrha:BAABLgAECn8jAAILAAkJjhUkGgDhAQALAAkJjhUkGgDhAQAAAA==.',
Mi='Mideel:BAAALgAECgcJEgAAAA==.Migal:BAAALgAECgEJAQABLgAECggJJgAhAHkZAA==.Migolbearcow:BAABLgAECn88AAITAAgJ9R3fBwBYAgATAAgJ9R3fBwBYAgAAAA==.Miinx:BAACLgAFFH8OAAITAAQJ5xv7BgBVAQATAAQJ5xv7BgBVAQAuAAQKfxoAAhMACAmHIPYFAIYCABMACAmHIPYFAIYCAAAA.Minervamon:BAAALgADCgMJAwAAAA==.Minotauren:BAAALgAECgcJEgAAAA==.Missed:BAABLgAECn8cAAIDAAgJIyN4IwBfAgADAAgJIyN4IwBfAgABLgAFFAIJBQAPAHENAA==.Missedshaped:BAAALgAECgIJAgABLgAFFAIJBQAPAHENAA==.Missedweaver:BAACLgAFFH8FAAIPAAIJcQ2hPQBnAAAPAAIJcQ2hPQBnAAAuAAQKfx4AAw8ACQntHPEKAMoCAA8ACQntHPEKAMoCABoAAQmEFMyDADsAAAAA.Misseed:BAAALgADCgYJBgABLgAFFAIJBQAPAHENAA==.Missrae:BAAALgADCgkJDwAAAA==.Mistyelliott:BAAALgADCgcJBwABLgAECgkJRwAfAJUeAA==.Miyuni:BAAALgADCgMJAwAAAA==.',
Mk='Mk:BAEBLgAECn8bAAIoAAgJyxbxBQDmAQAoAAgJyxbxBQDmAQABLgAECggJPQAaAGsjAA==.',
Ml='Mlglock:BAABLgAECn8XAAIWAAkJ9Bs+IgCMAgAWAAkJ9Bs+IgCMAgAAAA==.',
Mo='Mongocrush:BAAALgAECgUJBQAAAA==.Monyshot:BAAALgADCgEJAQAAAA==.Moocifur:BAAALgADCgkJEgAAAA==.Moonbeary:BAAALgAECgcJCwAAAA==.Mooniè:BAABLgAECn8iAAIQAAgJUwTOuQD1AAAQAAgJUwTOuQD1AAAAAA==.Moosensquirl:BAAALgADCgcJBwAAAA==.Moosenuts:BAAALgADCgkJAwAAAA==.Morzhul:BAAALgAECgYJDQAAAA==.Moxxii:BAABLgAECn8WAAMOAAgJlhz2DwANAgAOAAYJmiD2DwANAgAJAAMJjg9V5wCxAAAAAA==.',
Mu='Muradigme:BAAALgAECggJDwAAAA==.Mushufasa:BAAALgAECgEJAQAAAA==.Mutilusgore:BAABLgAECn80AAIeAAgJShhBEADMAQAeAAgJShhBEADMAQAAAA==.',
My='Myrium:BAAALgAECgQJCAAAAA==.Myshella:BAABLgAECn8aAAIKAAcJCRrRGADvAQAKAAcJCRrRGADvAQAAAA==.Myylus:BAAALgADCggJEgAAAA==.',
['Mö']='Mökes:BAACLgAFFH8cAAIiAAUJFyQHAgCrAQAiAAUJFyQHAgCrAQAuAAQKfyMAAiIACAlDI1UBABkDACIACAlDI1UBABkDAAAA.',
Na='Naijin:BAAALgADCgEJAQABLgAECgYJCgACAAAAAA==.Nasana:BAAALgADCgQJBAAAAA==.Navarra:BAAALgADCgEJAQAAAA==.Nawzero:BAAALgAECggJCQAAAA==.Nax:BAAALgAECgEJBQAAAA==.Nazagos:BAAALgAECgcJCQABLgAECgkJJQAMAPckAA==.Nazeiro:BAABLgAECn8RAAIhAAYJShDNeAA8AQAhAAYJShDNeAA8AQAAAA==.Nazzersaurus:BAABLgAECn8oAAIfAAgJChzzFwBzAgAfAAgJChzzFwBzAgAAAA==.',
Ne='Negies:BAAALgADCgYJBgAAAA==.Nekestinea:BAAALgADCgIJAgAAAA==.Nekomata:BAABLgAECn8cAAILAAgJbRd7HADMAQALAAgJbRd7HADMAQAAAA==.Nekosmasta:BAAALgADCggJCAAAAA==.Neodin:BAAALgADCgkJSwAAAA==.Newhamme:BAAALgAECggJDgAAAA==.',
Ni='Nickoftime:BAAALgAECgYJBgAAAA==.Nightjewel:BAAALgAECgQJBAAAAA==.Nightstalkër:BAAALgADCgcJBwABLgAECgkJEwACAAAAAA==.',
No='Noctevera:BAAALgADCgkJEQAAAA==.Noggs:BAAALgAECgEJAQAAAA==.Nokawa:BAAALgADCgYJBgAAAA==.Nokkas:BAAALgAECgcJCwAAAA==.Novadisc:BAAALgAECgEJAQAAAA==.',
Nu='Nuali:BAAALgADCgkJEQABLgAECgkJIgAKAIkYAA==.Numbasix:BAAALgAECgEJAQAAAA==.Numbers:BAACLgAFFH8IAAIgAAQJcRsmGABGAQAgAAQJcRsmGABGAQAuAAQKfx0AAiAACQl9HrEIAOQCACAACQl9HrEIAOQCAAAA.Numì:BAAALgAECgUJBAAAAA==.',
['Nê']='Nêrtt:BAABLgAECn9DAAQjAAkJMRmlBQCnAgAjAAkJMRmlBQCnAgAYAAcJkh/xBQCYAgAFAAUJACN6LABuAQAAAA==.',
Ob='Obard:BAAALgAECgUJBQAAAA==.',
Oc='Oche:BAAALgADCgcJEwABLgAECgkJKgAQALYTAA==.',
Od='Odysseus:BAAALgADCgMJAwAAAA==.',
Ok='Oketra:BAAALgADCgUJBQAAAA==.',
Ol='Olm:BAAALgAECgEJAQAAAA==.',
Om='Omniia:BAAALgAECgMJAwAAAA==.',
On='Onedog:BAAALgAECgEJAQAAAA==.Ontera:BAAALgAECgYJCgAAAA==.',
Or='Orala:BAABLgAECn8mAAIIAAkJRBRIGADpAQAIAAkJRBRIGADpAQAAAA==.Orlaya:BAAALgAECgEJAQAAAA==.Orý:BAABLgAECn82AAIcAAkJPh95DACJAgAcAAkJPh95DACJAgAAAA==.',
Os='Oslatem:BAABLgAECn8XAAMQAAYJ2hC9tAD+AAAQAAYJnw+9tAD+AAABAAIJqg8KDgBsAAAAAA==.',
Ot='Ottrekker:BAAALgADCgIJAgABLgAECggJEAACAAAAAA==.',
Ov='Overlie:BAAALgADCgUJBQAAAA==.',
Ox='Oxosorrel:BAAALgAECgEJAQAAAA==.',
Pa='Paladan:BAACLgAFFH8QAAMDAAQJjRvNKQBEAQADAAQJjRvNKQBEAQAlAAEJ+xNwBwA9AAAuAAQKfxoAAwMACQksImgLADMDAAMACQnwIWgLADMDACUABwkLIeAIAEgCAAAA.Paladeez:BAAALgAECgQJBAAAAA==.Pallyana:BAAALgAECgQJBQAAAA==.Palyboye:BAAALgADCgQJBAAAAA==.Pamorlin:BAAALgAECgEJBAAAAA==.Pandaemoni:BAAALgAECggJCgAAAA==.Pandamonea:BAAALgADCggJDgABLgAECggJCgACAAAAAA==.Pandamonium:BAAALgADCgYJCQABLgAECggJCgACAAAAAA==.Pandapunkt:BAAALgAECgYJDwAAAA==.Pandragon:BAAALgAECgIJAgABLgAECggJCgACAAAAAA==.Parallax:BAAALgAECgYJDgAAAA==.Parishealton:BAABLgAECn9HAAIfAAkJlR7nCQALAwAfAAkJlR7nCQALAwAAAA==.Pastybeard:BAABLgAECn8yAAMXAAkJuSTQAAAKAwAXAAkJuSTQAAAKAwAWAAkJGhoIIwBIAgAAAA==.Payday:BAAALgADCgkJCQAAAA==.Pazzuzu:BAAALgAFFAEJAQAAAA==.',
Pe='Penjamin:BAAALgAECgYJDgAAAA==.Pewnani:BAAALgADCgMJAwAAAA==.',
Ph='Phaestos:BAAALgAECgMJCgABLgAECggJNgALADQaAA==.',
Pi='Pinkburrito:BAAALgADCgEJAQAAAA==.',
Pl='Planetes:BAAALgAECgIJBAAAAA==.',
Po='Pontar:BAAALgAECgYJBgAAAA==.Pordobel:BAAALgADCgEJAQAAAA==.Portalnugget:BAAALgAECgEJAQABLgAFFAQJEQAfADISAA==.Portalz:BAAALgADCgYJBwABLgAFFAIJBQAPAHENAA==.Poulsbo:BAAALgAECgcJEgAAAA==.',
Pr='Prominence:BAABLgAECn8YAAIUAAcJwBxbDgBeAQAUAAcJwBxbDgBeAQAAAA==.Promisques:BAAALgADCgYJBgAAAA==.Proy:BAABLgAECn8WAAINAAcJ9xyRGwBUAgANAAcJ9xyRGwBUAgAAAA==.Prozak:BAABLgAECn83AAINAAgJLR5aEgCiAgANAAgJLR5aEgCiAgAAAA==.',
Ps='Psychofrenic:BAAALgADCgYJDgABLgAFFAIJAgACAAAAAA==.',
Pu='Puhlayden:BAABLgAECn8XAAMDAAgJax7sOAA/AgADAAcJ0B7sOAA/AgAgAAcJCQqJRQBiAQAAAA==.Puredragon:BAAALgADCgYJBgAAAA==.Purplehugs:BAAALgADCgEJAQAAAA==.',
['Pò']='Pòppy:BAAALgADCgcJBwAAAA==.',
Qu='Quikanez:BAABLgAECn8fAAMnAAgJJBMCDAB+AQAnAAgJJBMCDAB+AQAbAAQJ3A9USQDNAAAAAA==.Qulung:BAAALgADCgkJCQAAAA==.',
Ra='Rabyd:BAAALgAECgIJBAAAAA==.Radmane:BAAALgADCgEJAQAAAA==.Raegasm:BAAALgADCgQJBQAAAA==.Raein:BAAALgAECgYJDQAAAA==.Raithe:BAAALgADCgQJBAAAAA==.Raskela:BAABLgAECn8aAAIPAAkJZRwGDgB1AgAPAAkJZRwGDgB1AgAAAA==.Raskella:BAAALgAECgEJAQABLgAECgkJGgAPAGUcAA==.Ratboy:BAABLgAECn8eAAMGAAgJaxl7DwCtAgAGAAgJaxl7DwCtAgAHAAEJ2g7XIAAuAAAAAA==.Ratkiss:BAAALgADCgYJBgAAAA==.',
Re='Reckhn:BAAALgAECgEJAQAAAA==.Rellidana:BAAALgAECgkJEgAAAA==.Reportyrself:BAAALgAECgkJBgAAAA==.Reprieve:BAABLgAECn8rAAMSAAgJcSDEBwBjAgASAAgJcSDEBwBjAgAZAAQJrRKWdADoAAAAAA==.Retradormi:BAAALgAECgMJAwAAAA==.Reversal:BAAALgAFFAIJAgAAAA==.Rexe:BAABLgAFFH8HAAMUAAMJYwMHHACcAAAUAAMJYwMHHACcAAAMAAEJawGqLQBAAAAAAA==.Rexy:BAAALgAECgYJBwABLgAFFAMJBwAUAGMDAA==.',
Rh='Rhane:BAABLgAECn8UAAIMAAYJ2A0BjQALAQAMAAYJ2A0BjQALAQAAAA==.Rhazputin:BAAALgAECgQJBQAAAA==.Rhend:BAAALgADCgcJBwAAAA==.',
Ri='Riang:BAAALgAECgEJAQAAAA==.Rickcando:BAABLgAECn8UAAIcAAQJKwaNagCJAAAcAAQJKwaNagCJAAAAAA==.Ricshard:BAABLgAECn8zAAMiAAkJ6hx6DABZAQAWAAYJjhsIPgDXAQAiAAYJuRl6DABZAQAAAA==.Ridjeckgron:BAAALgAECgQJDAAAAA==.Righteouskat:BAAALgADCgIJAgAAAA==.Rindou:BAAALgAECgYJCgABLgAECgkJIgAFAGIjAA==.Rinea:BAABLgAECn8iAAMKAAkJiRi7FQAOAgAKAAkJiRi7FQAOAgAIAAEJ6gRqZgAsAAAAAA==.Riserphenex:BAABLgAECn8bAAIQAAcJmiPzJgBpAgAQAAcJmiPzJgBpAgABLgAFFAQJEgAGAB0fAA==.Risse:BAABLgAECn8qAAIQAAkJthM0OwAWAgAQAAkJthM0OwAWAgAAAA==.Ritari:BAAALgAECgcJBwAAAA==.Rizyl:BAAALgADCgIJAgAAAA==.',
Ro='Roarkitty:BAAALgAECgUJDAAAAA==.Rocknaw:BAABLgAECn8aAAIDAAkJrBbtTADIAQADAAkJrBbtTADIAQAAAA==.Rodgers:BAAALgAECggJDgABLgAFFAYJHgAeAMEbAA==.Rogaldorne:BAAALgAECgcJEAAAAA==.Rollinhotz:BAAALgAECgcJCwAAAA==.Romans:BAAALgADCgcJDwABLgAFFAQJCAAgAHEbAA==.Romina:BAAALgAECgYJCQAAAA==.Ronicary:BAAALgAECgEJAQAAAA==.Roofeed:BAAALgADCgEJAQAAAA==.Rospeteal:BAABLgAECn8/AAIiAAkJQRNXBwDCAQAiAAkJQRNXBwDCAQAAAA==.',
Ru='Ruben:BAAALgADCgYJCAAAAA==.Runefnar:BAAALgADCgkJEwAAAA==.Rungar:BAAALgAECggJCwAAAA==.Rungle:BAAALgAECgYJBgAAAA==.',
Ry='Rydmytotem:BAAALgADCgcJEwAAAA==.Ryjin:BAAALgADCgYJBgAAAA==.Rylia:BAAALgAECgUJDQAAAA==.Ryuhari:BAABLgAECn8/AAITAAkJPiQ5AQBCAwATAAkJPiQ5AQBCAwAAAA==.Ryujin:BAABLgAECn8xAAMGAAgJbhpFFQDdAQAGAAgJqRlFFQDdAQAHAAYJ3gx9EAAKAQAAAA==.Ryuseki:BAAALgADCgUJBQAAAA==.',
['Ró']='Ród:BAAALgAFFAEJAQABLgAFFAYJEAAQAD8PAA==.',
Sa='Saalira:BAAALgAECggJCQAAAA==.Sabellice:BAABLgAECn8zAAIDAAkJ4RK8RwDXAQADAAkJ4RK8RwDXAQAAAA==.Sadicia:BAAALgADCgIJAwAAAA==.Sakonna:BAABLgAFFH8RAAIIAAYJFRVqCwCCAQAIAAYJFRVqCwCCAQAAAA==.Salchydrak:BAAALgAFFAEJAQABLgAFFAQJCwANAG4QAA==.Salchygood:BAAALgAECgEJAQAAAA==.Salinoria:BAABLgAECn8hAAIhAAkJ6QpQVgBrAQAhAAkJ6QpQVgBrAQABLgAECgkJIgAKAIkYAA==.Saltyfingers:BAAALgADCgkJEAAAAA==.Samwell:BAAALgADCgkJHwAAAA==.Sandymaw:BAAALgAECgQJCAABLgAFFAQJCAAWAAMHAA==.Saniroin:BAAALgADCgIJAgAAAA==.Sarlius:BAABLgAECn8lAAIMAAkJ9yTBAAC5AwAMAAkJ9yTBAAC5AwAAAA==.Satyrical:BAAALgAECgQJBAABLgAECgQJCwACAAAAAA==.Sausagecat:BAAALgADCgEJAQAAAA==.Savin:BAABLgAECn8ZAAIgAAcJGgijQgAgAQAgAAcJGgijQgAgAQAAAA==.',
Sc='Scarecrow:BAAALgADCgEJAQAAAA==.Scargrimm:BAAALgAECgcJBgAAAA==.Scavenger:BAABLgAECn8UAAIUAAgJIwFwKwBZAAAUAAgJIwFwKwBZAAAAAA==.Schorsha:BAAALgAECgYJDwAAAA==.',
Se='Securityx:BAAALgADCgEJAQAAAA==.Selkamonk:BAACLgAFFH8GAAIPAAIJNhm3NQCPAAAPAAIJNhm3NQCPAAAuAAQKf0MAAw8ACQnbJd8AANIDAA8ACQnbJd8AANIDABoAAQkAAJ91AEAAAAAA.Seniorbold:BAAALgAECgYJDAAAAA==.Sentrina:BAACLgAFFH8WAAIjAAUJKBJHEgBNAQAjAAUJKBJHEgBNAQAuAAQKfywAAiMACQnPGNkPAD0CACMACQnPGNkPAD0CAAAA.Seramon:BAAALgADCgQJBAABLgAECgkJLgAdAMYgAA==.Seraph:BAAALgAECgEJAgAAAA==.Serenìty:BAAALgADCgMJAwAAAA==.Seshy:BAABLgAECn8XAAMIAAYJvwspUACnAAAIAAYJvwspUACnAAAEAAMJpAdGVAB6AAABLgAFFAQJCAAWAAMHAA==.Seshymutedme:BAACLgAFFH8IAAMWAAQJAwckWgD6AAAWAAQJoAUkWgD6AAAXAAEJawlwIABIAAAuAAQKfyEABBYACQm1F7c3AO4BABYACAm1F7c3AO4BACIABAmQCi85ANAAABcAAgncEPMyADwAAAAA.',
Sh='Shadian:BAAALgADCgIJAgAAAA==.Shamanagins:BAAALgAECgQJBAAAAA==.Shanndril:BAAALgADCgYJBgAAAA==.Shannon:BAAALgADCgkJEQABLgAECggJHgAgAO4OAA==.Shannoon:BAABLgAECn8iAAIlAAgJAQilIAD0AAAlAAgJAQilIAD0AAAAAA==.Shekzeer:BAAALgAFFAIJAgABLgAFFAQJEgAGAB0fAA==.Shimmiiee:BAAALgAECgYJCAAAAA==.Shing:BAACLgAFFH8FAAIkAAQJiB2QFABZAQAkAAQJiB2QFABZAQAuAAQKfyQAAyQACQm8IP8VAOoBACQACQm8IP8VAOoBABoABQnaDSpLAOUAAAAA.Shiverr:BAAALgAECgcJDgAAAA==.Shocktard:BAAALgAECgkJCQABLgAECgkJJQAJAEsjAA==.Shoftìel:BAAALgADCgcJCgAAAA==.Shxt:BAAALgADCgIJAgAAAA==.',
Si='Sivrak:BAAALgADCggJBQAAAA==.',
Sk='Skizem:BAAALgADCgIJAgAAAA==.Skott:BAAALgAECgcJDgAAAA==.',
Sl='Sleepadin:BAAALgAECggJDgAAAA==.Sleepyr:BAABLgAECn8eAAMFAAgJswtxKQBzAQAFAAgJswtxKQBzAQAjAAEJTwGHQQAOAAAAAA==.Slobkabob:BAAALgAECgEJAwAAAA==.Slæmt:BAAALgAECgEJAQABLgAECgcJBwACAAAAAA==.',
Sm='Smol:BAAALgAECgQJCwAAAA==.Smolside:BAAALgADCgEJAQAAAA==.',
Sn='Snowi:BAAALgAFFAEJAQAAAA==.',
So='Solignis:BAACLgAFFH8wAAMZAAcJtiXbAACFAgAZAAcJtiXbAACFAgASAAMJYSRjIgC4AAAuAAQKf0QAAxkACQmEJsYAANUDABkACQmEJsYAANUDABIAAQm1I8EyAGgAAAAA.Songs:BAAALgAECgMJAwABLgAFFAQJCAAgAHEbAA==.Soohots:BAABLgAECn8XAAIfAAgJ/RlJHABQAgAfAAgJ/RlJHABQAgAAAA==.Soular:BAAALgADCgMJAwAAAA==.',
Sp='Sparklehappy:BAABLgAECn8lAAMdAAkJzx8CBADmAgAdAAkJzx8CBADmAgAUAAUJSxgXQgBQAQAAAA==.Spiritdurk:BAAALgADCggJDAAAAA==.Spog:BAAALgAECggJEgAAAA==.Spoghasm:BAABLgAECn8vAAITAAkJYyQsAQBFAwATAAkJYyQsAQBFAwAAAA==.Spookyghost:BAAALgAECgQJBAAAAA==.Sposcre:BAAALgADCgUJBQAAAA==.Spothoof:BAACLgAFFH8bAAMcAAYJ4xmIDwB5AQAcAAUJ4xmIDwB5AQARAAEJAABbFgAAAAAuAAQKfysAAhwACQnsH4IIAMICABwACQnsH4IIAMICAAAA.Sprout:BAAALgADCgQJBAAAAA==.',
St='Stalari:BAAALgAECgcJDQAAAA==.Starfoxx:BAAALgAECgEJAgAAAA==.Starshield:BAAALgAECgEJAQABLgAFFAQJCgAJAPcSAA==.Stcupertino:BAABLgAECn8hAAMgAAkJ2ga8NgBcAQAgAAkJ2ga8NgBcAQADAAEJzwXbVQEoAAAAAA==.Steamedham:BAAALgAECgcJBwAAAA==.Steeljustice:BAAALgAECgYJDAAAAA==.Stellalou:BAAALgAECgEJBAAAAA==.Stormstout:BAAALgADCgIJAgAAAA==.Storri:BAABLgAECn83AAMKAAkJiBb5EgAtAgAKAAkJiBb5EgAtAgAIAAYJ7gcfSADIAAAAAA==.Storrii:BAAALgAECgYJDAAAAA==.Stryranger:BAAALgAECgUJBQAAAA==.',
Su='Submersed:BAAALgAECgMJAwAAAA==.Suehunter:BAABLgAECn8VAAIMAAYJCgfynADqAAAMAAYJCgfynADqAAAAAA==.Sufferinhero:BAAALgAECgMJAwABLgAFFAMJDAAnAPgiAA==.Sumarune:BAAALgAECgEJAgAAAA==.Suturi:BAAALgADCggJCAAAAA==.Suvi:BAAALgADCgEJBQAAAA==.Suzuya:BAAALgAECgUJDAAAAA==.',
Sw='Swiftly:BAABLgAFFH8GAAIHAAMJzhofBgD1AAAHAAMJzhofBgD1AAAAAA==.Swiftmage:BAACLgAFFH8rAAIQAAcJ2yATCgBmAgAQAAcJ2yATCgBmAgAuAAQKfzwAAhAACQmJJtUAAPYDABAACQmJJtUAAPYDAAAA.',
Sy='Sylvian:BAAALgAECgQJBgAAAA==.Syndragonkin:BAAALgAECgkJCQAAAA==.Syndrome:BAABLgAECn8iAAMaAAgJmhdCGgDHAQAaAAgJmhdCGgDHAQAPAAQJGgbYVQB4AAAAAA==.Syrelea:BAAALgADCgIJAgAAAA==.Sywren:BAAALgAECgEJAwABLgAECgQJCwACAAAAAA==.',
Sz='Szeto:BAABLgAECn8jAAMNAAkJFhaYHABNAgANAAkJFhaYHABNAgARAAEJXg3qMwA1AAAAAA==.',
Ta='Talyndis:BAACLgAFFH8jAAMUAAgJkR0bAwAyAgAUAAgJah0bAwAyAgAMAAMJMiTnVwDJAAAuAAQKfycAAxQACQnSIyADAHgDABQACQm2IiADAHgDAAwABAn0HVtnAFwBAAAA.Tamyr:BAAALgADCgMJAwABLgAECgQJBgACAAAAAA==.Tashido:BAAALgAECgcJDwAAAA==.Taze:BAAALgAFFAIJBAABLgAFFAQJDQAMAFgQAA==.Tazjiingo:BAABLgAECn8ZAAMfAAYJmRgONwCpAQAfAAYJmRgONwCpAQALAAUJuhDCRgDUAAAAAA==.',
Te='Teanie:BAAALgAECgYJBgAAAA==.Tenebrium:BAAALgAECgEJBAAAAA==.Terhali:BAAALgAECgcJCwAAAA==.Terrika:BAABLgAECn8gAAIMAAgJzBD+UACWAQAMAAgJzBD+UACWAQAAAA==.Tetshajeh:BAABLgAECn8oAAIZAAgJnSXeBQDwAgAZAAgJnSXeBQDwAgAAAA==.Teyliana:BAAALgAECgcJEgAAAA==.',
Th='Theanimal:BAAALgADCgcJCAAAAA==.Therasa:BAAALgAECgQJBQAAAA==.Thewizardguy:BAAALgAECgUJCAAAAA==.Thillarick:BAABLgAECn80AAIZAAgJtSUWBwDeAgAZAAgJtSUWBwDeAgAAAA==.Thiss:BAAALgAECgQJCQAAAA==.Thiya:BAABLgAECn8aAAIDAAgJOA1RfwBVAQADAAgJOA1RfwBVAQAAAA==.Thorvard:BAABLgAECn8XAAMeAAYJphqjGgBNAQAeAAYJphqjGgBNAQAZAAEJVQFttQAcAAAAAA==.Thromanor:BAABLgAECn8XAAIZAAYJbBerOABOAQAZAAYJbBerOABOAQAAAA==.',
Ti='Tirachill:BAAALgAECgEJAQAAAA==.Tiramisú:BAAALgAECgYJEQAAAA==.Tiranmyashol:BAABLgAECn8gAAIZAAcJ6heWLwDxAQAZAAcJ6heWLwDxAQAAAA==.',
To='Tolken:BAAALgAECgIJAgAAAA==.Too:BAAALgAECgUJBgAAAA==.Toothdk:BAABLgAECn8oAAIJAAgJNCLLGQCYAgAJAAgJNCLLGQCYAgAAAA==.Toppo:BAABLgAECn8uAAIlAAkJ7CFQAgD9AgAlAAkJ7CFQAgD9AgAAAA==.Torfnar:BAAALgAECggJDgAAAA==.Toxicophobia:BAAALgAECgUJCAAAAA==.',
Tr='Tralle:BAAALgAECgQJCAAAAA==.Treebreak:BAABLgAECn8mAAIfAAkJlRDGOQCcAQAfAAkJlRDGOQCcAQAAAA==.Treefity:BAAALgADCgIJAgAAAA==.Trinky:BAAALgAECgUJDQAAAA==.Troublems:BAAALgAECgYJEwAAAA==.',
Ts='Tshi:BAAALgAECgIJAgAAAA==.',
Tu='Turanx:BAAALgAECgIJAgAAAA==.Tutemkhan:BAAALgAECgYJDQAAAA==.',
Tw='Twigrets:BAAALgAECgYJDwAAAA==.',
Ty='Tyrandrea:BAAALgAECgUJDQAAAA==.',
Ud='Udari:BAAALgAECgEJBAAAAA==.',
Ug='Ugîn:BAAALgAECgIJAgAAAA==.',
Um='Umbreona:BAAALgAECgMJAwAAAA==.Umàdbrah:BAABLgAECn8zAAIMAAkJCR/5EQCsAgAMAAkJCR/5EQCsAgAAAA==.',
Un='Unbelievable:BAABLgAECn8vAAIbAAgJjBPuFwCjAQAbAAgJjBPuFwCjAQAAAA==.Unclechuck:BAAALgADCgQJBwAAAA==.Unholylaezel:BAAALgAECgMJCQAAAA==.',
Va='Vaein:BAABLgAECn8YAAIiAAgJwRJHCQCXAQAiAAgJwRJHCQCXAQAAAA==.Valamor:BAABLgAECn8xAAMgAAkJvxo5GQAmAgAgAAkJvxo5GQAmAgAlAAEJdQXZUwAVAAAAAA==.Valencia:BAAALgADCgIJAgAAAA==.Valicela:BAAALgAECgUJBwAAAA==.Vandamage:BAAALgADCgMJAwAAAA==.Vani:BAAALgAECgQJCwAAAA==.Varenea:BAABLgAECn8ZAAIIAAcJrAcSQADrAAAIAAcJrAcSQADrAAAAAA==.Varia:BAAALgADCgYJBgABLgAECgkJJQAJAEsjAA==.Vasharis:BAAALgADCgYJBgAAAA==.',
Ve='Veefib:BAABLgAECn8UAAIcAAgJ1xeLKgDCAQAcAAgJ1xeLKgDCAQAAAA==.Velent:BAAALgADCgEJAQAAAA==.Velhari:BAACLgAFFH8GAAIhAAQJuBhPNAAsAQAhAAQJuBhPNAAsAQAuAAQKfysAAycABgmRJOMGAAQCACEABgnsIUQsAE0CACcABgmRJOMGAAQCAAEuAAUUBAkSAAYAHR8A.Velicerus:BAAALgAECgEJAQAAAA==.Velliri:BAAALgAECgMJAwAAAA==.Velvettwitch:BAABLgAECn8uAAIiAAgJRBIsCgCDAQAiAAgJRBIsCgCDAQAAAA==.Verahla:BAAALgADCgkJHQAAAA==.Vermis:BAAALgAECgQJBwAAAA==.Verona:BAAALgADCgMJAwAAAA==.Veryaverage:BAABLgAECn8dAAIQAAgJ7xuJUwDKAQAQAAgJ7xuJUwDKAQAAAA==.Vexation:BAAALgAECgUJCwAAAA==.Vexxd:BAAALgAECgUJDAAAAA==.',
Vi='Vicarious:BAABLgAECn8iAAINAAgJPCItCQAJAwANAAgJPCItCQAJAwAAAA==.Vidreaux:BAABLgAECn8/AAIBAAkJ5hjJAQBfAgABAAkJ5hjJAQBfAgAAAA==.Viltry:BAAALgAECggJDwAAAA==.Vipora:BAACLgAFFH8MAAIFAAMJfhyzKgD8AAAFAAMJfhyzKgD8AAAuAAQKfz8AAwUACQkcIn4EAAkDAAUACQkcIn4EAAkDABgABAnuCkArAMMAAAAA.Visp:BAAALgAECgIJBAAAAA==.',
Vo='Volaura:BAAALgADCgQJBwAAAA==.Volzara:BAABLgAECn8aAAIIAAgJ9xMKGgAPAgAIAAgJ9xMKGgAPAgAAAA==.Voìde:BAAALgAECgMJBAAAAA==.',
Vy='Vynesra:BAAALgADCgEJAgAAAA==.',
Wa='Walleroot:BAAALgADCgMJAwABLgAECgkJLAAfAJMUAA==.Wavy:BAAALgAECgEJAgAAAA==.',
We='Wetnurse:BAAALgADCgcJBwAAAA==.',
Wh='Whirz:BAAALgAECgkJEAAAAA==.Whizglizzy:BAAALgADCgQJBAAAAA==.Whosethetank:BAAALgADCgcJEgABLgADCgEJAQACAAAAAA==.',
Wi='Wick:BAAALgAECgIJAwABLgAECgQJCwACAAAAAA==.',
Wm='Wmz:BAAALgAECgQJBwAAAA==.',
Wo='Wolfpup:BAAALgAECgcJEgABLgAECggJJAADAFQZAA==.Wolfíe:BAAALgAECgIJAwAAAA==.',
Ww='Wwalle:BAAALgAECgUJBwABLgAECgkJLAAfAJMUAA==.',
Xe='Xenarra:BAAALgADCgUJBQAAAA==.',
Xz='Xzavier:BAAALgAECgQJBAAAAA==.',
['Xä']='Xänsus:BAAALgAECgEJAQAAAA==.',
Ya='Yandros:BAAALgADCgIJAgAAAA==.Yansaa:BAABLgAECn8uAAMfAAgJ7R39EwCYAgAfAAgJ7R39EwCYAgAmAAIJUBBUMgBrAAAAAA==.Yasutora:BAAALgADCgYJCgABLgAECgkJLgAdAMYgAA==.',
Yf='Yfelshammy:BAABLgAECn8+AAINAAkJNhkxFACQAgANAAkJNhkxFACQAgAAAA==.',
Yi='Yisselda:BAAALgAECgEJAQAAAA==.',
Yo='Yogiebear:BAAALgADCgUJBQAAAA==.Yogsøthoth:BAAALgADCgYJBgAAAA==.',
Yr='Yrsea:BAAALgADCgIJAgAAAA==.',
Yu='Yubel:BAAALgAECgQJBAABLgAECgcJGQAEADsOAA==.',
Za='Zaevenia:BAAALgADCgkJCwAAAA==.Zakka:BAAALgADCgQJBgAAAA==.Zalraz:BAAALgAECgIJAgAAAA==.Zanebusby:BAABLgAECn8dAAIiAAgJfBZlCACrAQAiAAgJfBZlCACrAQAAAA==.Zannahh:BAABLgAECn8nAAIQAAkJygjDbgCDAQAQAAkJygjDbgCDAQAAAA==.Zaraa:BAABLgAECn8UAAIRAAYJriEFCgAzAgARAAYJriEFCgAzAgAAAA==.Zaraë:BAABLgAECn8mAAIhAAkJUyAKDADUAgAhAAkJUyAKDADUAgAAAA==.Zatharis:BAABLgAECn8hAAIMAAgJVBnLLAATAgAMAAgJVBnLLAATAgAAAA==.',
Ze='Zepp:BAAALgAECgEJAgAAAA==.Zerax:BAABLgAECn8VAAIQAAcJ9Q+viwBFAQAQAAcJ9Q+viwBFAQAAAA==.Zeroshaman:BAAALgAECgQJBAAAAA==.',
Zi='Ziljin:BAAALgADCgkJCQAAAA==.',
Zm='Zmona:BAAALgAECgIJAgABLgAECgkJJQAJAEsjAA==.',
Zz='Zzella:BAACLgAFFH8MAAIgAAQJDiK9EQCHAQAgAAQJDiK9EQCHAQAuAAQKfzMAAyAACQluIxoFAC8DACAACQluIxoFAC8DAAMABgl/HgBYAKsBAAAA.',
['Ða']='Ðabzilla:BAABLgAECn8dAAMgAAgJmBstHwDzAQAgAAgJmBstHwDzAQADAAIJhg/8JQFnAAAAAA==.',
['Ðr']='Ðracotalon:BAAALgAECgYJCgAAAA==.Ðragonbeast:BAAALgADCgkJEgAAAA==.Ðragonshaft:BAABLgAECn8vAAMMAAgJQx+eGgBwAgAMAAgJQx+eGgBwAgAUAAEJAAC1nAAEAAAAAA==.',
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
