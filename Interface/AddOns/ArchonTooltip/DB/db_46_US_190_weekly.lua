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

local lookup = {'Mage-Arcane','Unknown-Unknown','Paladin-Retribution','Priest-Discipline','Evoker-Augmentation','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Unholy','Druid-Balance','Hunter-BeastMastery','Shaman-Restoration','DeathKnight-Blood','Monk-Mistweaver','Mage-Frost','Shaman-Enhancement','Warrior-Arms','Druid-Guardian','Hunter-Marksmanship','DeathKnight-Frost','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Evoker-Devastation','Warrior-Fury','Priest-Holy','Monk-Windwalker','DemonHunter-Havoc','Shaman-Elemental','Hunter-Survival','Warrior-Protection','Druid-Restoration','Paladin-Holy','DemonHunter-Devourer','Warlock-Destruction','Evoker-Preservation','Monk-Brewmaster','Paladin-Protection','Druid-Feral','DemonHunter-Vengeance','Rogue-Outlaw',}
local provider = {region='US',realm='Shadowsong',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abbinormal:BAAALgADCgUJBAAAAA==.Abysma:BAAALgAECgEJAQAAAA==.',
Ad='Adoran:BAAALgADCgEJAQAAAA==.Adorian:BAAALgAECgEJAgAAAA==.Adrenaleen:BAAALgAECgUJCQAAAA==.',
Ae='Aeosi:BAAALgADCgEJAQAAAA==.Aeriss:BAAALgADCgUJCAAAAA==.Aertin:BAAALgADCgQJBAABLgAECggJJQABAOQYAA==.Aeryhn:BAAALgADCgcJDAABLgAECgYJDwACAAAAAA==.Aezili:BAAALgAECgUJEAAAAA==.',
Af='Afkatie:BAAALgAECgQJCwAAAA==.',
Ag='Agaruu:BAAALgAECgYJBgAAAA==.Agerol:BAABLgAECn8sAAIDAAgJHSIqFACuAgADAAgJHSIqFACuAgAAAA==.Agnin:BAAALgADCgcJDgAAAA==.',
Ak='Akafabu:BAAALgAECgQJDAABLgAFFAUJEgAEAAUNAA==.Akumunter:BAAALgAECgYJEQAAAA==.Akuryujin:BAABLgAECn8pAAIFAAkJEA/PIgCiAQAFAAkJEA/PIgCiAQAAAA==.Akätsuki:BAABLgAECn8iAAIGAAkJohIsEgDxAQAGAAkJohIsEgDxAQAAAA==.',
Al='Alacardias:BAABLgAECn8gAAIDAAgJ1h2GMQAZAgADAAgJ1h2GMQAZAgAAAA==.Alackoflust:BAAALgAECgEJAQABLgAECgQJCgACAAAAAA==.Aladistra:BAAALgADCgMJAwAAAA==.Albert:BAAALgADCgIJAgAAAA==.Alcaedra:BAAALgADCggJCAAAAA==.Alcapwnz:BAAALgADCgYJCQAAAA==.Alinoda:BAAALgADCgIJAgAAAA==.Alleril:BAABLgAECn9AAAMGAAkJDhIQEgDyAQAGAAkJPhAQEgDyAQAHAAgJKw/aBwDeAQAAAA==.Alley:BAAALgADCgUJCgAAAA==.Alpha:BAAALgAECgIJAgAAAA==.',
Am='Amäri:BAACLgAFFH8SAAIEAAUJBQ2hFgBhAQAEAAUJBQ2hFgBhAQAuAAQKfy8AAgQACQmuFSgSACQCAAQACQmuFSgSACQCAAAA.',
An='Anassand:BAABLgAECn8lAAIIAAkJSyM5EADLAgAIAAkJSyM5EADLAgAAAA==.Andimorph:BAABLgAECn8XAAIJAAgJmRwmDgBQAgAJAAgJmRwmDgBQAgAAAA==.Anema:BAAALgADCgQJBAABLgAECgMJBgACAAAAAA==.Angeleria:BAABLgAECn8dAAIKAAkJOSBSDgC5AgAKAAkJOSBSDgC5AgAAAA==.Antebellum:BAAALgAECgcJBQAAAA==.',
Aq='Aqiqi:BAAALgAECgQJCgAAAA==.Aquashade:BAAALgAECgUJDgABLgAFFAUJBwALAEgHAA==.Aquaterra:BAACLgAFFH8HAAILAAUJSAcZIAAvAQALAAUJSAcZIAAvAQAuAAQKfzcAAgsACQnXI/QDAFYDAAsACQnXI/QDAFYDAAAA.Aquina:BAAALgAECgYJBgABLgAFFAUJBwALAEgHAA==.',
Ar='Arakadia:BAABLgAECn82AAMIAAgJMxeBRADTAQAIAAgJ3xSBRADTAQAMAAUJBhNTKADjAAAAAA==.Aravena:BAAALgADCgcJAwAAAA==.Archetyepe:BAAALgAECgIJBQAAAA==.Arisana:BAAALgAECgQJBwAAAA==.Aruteeru:BAABLgAECn8cAAINAAgJlR45DACiAgANAAgJlR45DACiAgAAAA==.',
As='Asathen:BAAALgADCgEJAQAAAA==.Aseanna:BAAALgAECgcJDwAAAA==.Ashadala:BAAALgAECgYJBwAAAA==.Astallivan:BAAALgADCgkJFQAAAA==.Astrevia:BAAALgAECgYJBgAAAA==.',
Au='Augabeks:BAACLgAFFH8OAAIFAAQJBBH4IwANAQAFAAQJBBH4IwANAQAuAAQKfyMAAgUACAmpFaEZAAACAAUACAmpFaEZAAACAAEuAAMKBwkHAAIAAAAA.Auralada:BAABLgAECn8lAAMBAAgJ5Bh/BAACAgABAAcJcht/BAACAgAOAAgJ4hIseABrAQAAAA==.Auxhunt:BAAALgADCgkJDQAAAA==.Auxiliator:BAAALgADCgYJCgABLgADCggJCgACAAAAAA==.',
Av='Avataroffury:BAAALgAECggJEQABLgAECgkJJQAIAEsjAA==.',
Ay='Ayala:BAABLgAFFH8VAAIDAAUJLSIFCQDUAQADAAUJLSIFCQDUAQAAAA==.Ayessa:BAAALgAECgYJEwABLgAECggJCgACAAAAAA==.',
Az='Azaireos:BAAALgAECgMJAwAAAA==.Azulpunkt:BAABLgAECn8sAAIPAAgJyR46BgBIAgAPAAgJyR46BgBIAgAAAA==.Azzapp:BAABLgAECn8eAAIQAAYJ+xCvJgAKAQAQAAYJ+xCvJgAKAQAAAA==.',
Ba='Baddaboomkin:BAABLgAECn8XAAMJAAgJPBTAGgDGAQAJAAgJPBTAGgDGAQARAAUJ0wHTSwBCAAAAAA==.Bakreingol:BAAALgAECgEJAQABLgAECgcJCwACAAAAAA==.Bammboom:BAAALgAECgEJAQAAAA==.Barbedwire:BAAALgAECgcJBAAAAA==.Baree:BAAALgAECgMJBAAAAA==.',
Be='Bearmao:BAABLgAECn81AAMKAAgJIBikLAABAgAKAAgJxRekLAABAgASAAcJaQx8QQBTAQAAAA==.Bearserk:BAAALgAECgMJBwAAAA==.Beastknight:BAAALgAECgYJDgAAAA==.Beastrunner:BAAALgADCgkJEQABLgAECgYJDgACAAAAAA==.Beknight:BAABLgAECn8WAAQIAAcJ6xJxpwD4AAAIAAYJ8BNxpwD4AAAMAAMJ5AiyRABOAAATAAEJzRUVFgA5AAABLgADCgcJBwACAAAAAA==.Belfas:BAABLgAECn8YAAIPAAcJnBr7DACrAQAPAAcJnBr7DACrAQAAAA==.Bellybutton:BAAALgAECgkJDgAAAA==.Benafflok:BAACLgAFFH8PAAMUAAQJUxudNQA6AQAUAAQJUxudNQA6AQAVAAEJRAt9BgBRAAAuAAQKfyYAAxQACAk1JLgSAKACABQACAkBJLgSAKACABUABwn9H3YDAGMCAAEuAAEKCAkIAAIAAAAA.Bertu:BAAALgADCgEJAQAAAA==.',
Bi='Bigblight:BAAALgADCgEJAwAAAA==.Bigduck:BAAALgAECgUJCgAAAA==.Biggayjohn:BAAALgAECgYJEgAAAA==.Bigknighter:BAAALgAECgYJDgAAAA==.',
Bl='Blackclover:BAACLgAFFH8MAAILAAQJLBbTJAAYAQALAAQJLBbTJAAYAQAuAAQKfysAAgsACQlIG18bAEMCAAsACQlIG18bAEMCAAAA.Blackpink:BAAALgADCggJEwAAAA==.Blandicus:BAAALgADCgcJBwAAAA==.',
Bo='Boppaheks:BAAALgADCgcJBwAAAA==.Bowless:BAAALgAECgcJCAABLgAECgkJGAAUANwYAA==.',
Br='Brawnstone:BAAALgAECgEJAQAAAA==.Brewsleroy:BAAALgADCgcJDQAAAA==.Brewtypoppin:BAAALgADCgQJBAAAAA==.Brey:BAAALgADCgMJAwAAAA==.Brightshield:BAAALgAECgUJBQAAAA==.Brohomir:BAAALgAECgEJAQAAAA==.Bronze:BAABLgAECn8gAAINAAcJTA4/PgAcAQANAAcJTA4/PgAcAQAAAA==.Brunee:BAABLgAECn8WAAIWAAgJzwpMJwCeAQAWAAgJzwpMJwCeAQAAAA==.Bruute:BAABLgAECn82AAIQAAgJIiWgAgD0AgAQAAgJIiWgAgD0AgAAAA==.',
Bu='Budplatinum:BAABLgAECn8cAAIXAAgJkApnCgBUAQAXAAgJkApnCgBUAQAAAA==.Buffbuffheal:BAAALgAECgMJAwABLgAECgYJCgACAAAAAA==.Buhemoth:BAAALgAECgcJDgAAAA==.Bumi:BAAALgADCgQJBAAAAA==.Butters:BAAALgADCgEJAQAAAA==.',
['Bâ']='Bâït:BAAALgAECgYJCgABLgAECgcJBgACAAAAAA==.',
['Bã']='Bãìt:BAAALgAECgUJBQABLgAECgcJBgACAAAAAA==.',
Ca='Caemaris:BAAALgADCgQJBAAAAA==.Cairo:BAABLgAECn8XAAIYAAgJrhhLIwA7AgAYAAgJrhhLIwA7AgAAAA==.Cakes:BAABLgAECn8aAAIZAAYJJBXSLgAyAQAZAAYJJBXSLgAyAQAAAA==.Calai:BAAALgADCgkJEwAAAA==.Canadiian:BAAALgAECgYJDwAAAA==.Capitalchaos:BAABLgAECn8tAAIYAAgJpRwxFwAQAgAYAAgJpRwxFwAQAgAAAA==.Cassandraa:BAAALgAECgQJBAAAAA==.',
Ce='Cearrdorn:BAAALgAECgMJBQABLgAECggJNAADAD0iAA==.Cearreotadh:BAAALgADCgQJBAAAAA==.Celticrock:BAAALgAECgEJAQAAAA==.Ceviche:BAACLgAFFH8PAAIaAAUJFBrXCwA9AQAaAAUJFBrXCwA9AQAuAAQKfx4AAhoACQmhIrgFACgDABoACQmhIrgFACgDAAAA.Ceàrrdòrn:BAABLgAECn80AAIDAAgJPSJgJwBEAgADAAgJPSJgJwBEAgAAAA==.',
Ch='Chaskitty:BAAALgAECgIJAgAAAA==.Cheetahgirl:BAAALgAECgEJBAAAAA==.Chickenjoy:BAAALgADCgcJBwAAAA==.Chillzmatic:BAACLgAFFH8JAAIbAAQJoAsrDQAUAQAbAAQJoAsrDQAUAQAuAAQKfxwAAhsABgnHI5wYAAICABsABgnHI5wYAAICAAAA.Chirri:BAAALgAECgQJCwAAAA==.Chondriac:BAABLgAECn8eAAIcAAgJRBrlFgADAgAcAAgJRBrlFgADAgAAAA==.Chow:BAAALgADCgQJBAAAAA==.Chrisdirect:BAAALgADCgQJBAAAAA==.Chudbucket:BAABLgAECn8oAAMdAAcJLR6UEQAFAgAdAAcJLR6UEQAFAgASAAUJvRdkPABtAQAAAA==.Chàssy:BAAALgAECgIJAgAAAA==.',
Ci='Cilantro:BAAALgADCgEJAQABLgAECgcJEQACAAAAAA==.Cinabun:BAAALgADCgIJAgAAAA==.Cirillø:BAABLgAECn8aAAIeAAkJVh0xCABVAgAeAAkJVh0xCABVAgAAAA==.',
Cl='Clinictrials:BAAALgAECggJEQAAAA==.Cloverblack:BAAALgADCgEJAQAAAA==.',
Co='Corbis:BAABLgAECn8cAAMfAAcJEgnuXgD5AAAfAAcJEgnuXgD5AAAJAAIJhQZHgQAvAAAAAA==.Covidmage:BAAALgADCgUJCgAAAA==.Cowpatty:BAAALgADCgYJFQAAAA==.',
Cr='Crepitate:BAAALgAECgEJAQABLgAECgcJBgACAAAAAA==.Crunchwich:BAAALgAECgYJEQAAAA==.',
Cu='Cuchi:BAAALgADCgkJDAAAAA==.Cutename:BAAALgAECgYJEwAAAA==.',
Cy='Cynamyn:BAAALgAECgYJEQAAAA==.Cyraea:BAAALgAECgMJCQAAAA==.',
Cz='Czeskilight:BAABLgAECn8iAAIEAAkJORGxGADgAQAEAAkJORGxGADgAQAAAA==.',
['Câ']='Câl:BAAALgAECgEJAQAAAA==.',
['Cå']='Cåle:BAAALgAECgUJDQAAAA==.',
Da='Daane:BAAALgAECgMJAwAAAA==.Dabadwarrior:BAABLgAECn88AAMYAAgJSxicJQClAQAYAAgJXxWcJQClAQAeAAcJyQ8+GwA0AQAAAA==.Dabs:BAAALgAECgEJAQAAAA==.Dabzilla:BAAALgAECgQJBAABLgAECggJHQAgAJgbAA==.Dabzîlla:BAAALgADCggJDAABLgAECggJHQAgAJgbAA==.Daffadill:BAAALgADCgEJAQAAAA==.Dakhran:BAAALgADCgUJFAAAAA==.Dan:BAAALgAECgcJDgAAAA==.Danero:BAAALgAECgEJAQAAAA==.Darkchangu:BAAALgAECgYJCQAAAA==.Darkdemon:BAABLgAECn8lAAIhAAgJ2xFOSgCFAQAhAAgJ2xFOSgCFAQAAAA==.Darknessz:BAAALgADCgkJDwAAAA==.Darkovia:BAAALgADCgMJAwAAAA==.Darkshyne:BAAALgADCgcJBwAAAA==.Darlord:BAAALgAECgYJEQAAAA==.',
De='Deagle:BAACLgAFFH8RAAIGAAQJHR/tCwB4AQAGAAQJHR/tCwB4AQAuAAQKf0AAAgYACAn7JX0DAPQCAAYACAn7JX0DAPQCAAAA.Deathpunkt:BAAALgAECgQJBgAAAA==.Deedubbya:BAAALgADCgMJAwAAAA==.Defense:BAAALgADCgkJIQAAAA==.Delryd:BAAALgAECgYJEQAAAA==.Demonfrog:BAACLgAFFH8IAAIIAAQJawvAXAAVAQAIAAQJawvAXAAVAQAuAAQKfygAAggACQlkF6lDANUBAAgACQlkF6lDANUBAAAA.Demônlock:BAAALgAECgYJEQAAAA==.Desideria:BAABLgAECn8sAAIUAAgJIAb3fAAqAQAUAAgJIAb3fAAqAQAAAA==.Desynn:BAABLgAECn80AAIUAAgJ+hcdLQAMAgAUAAgJ+hcdLQAMAgAAAA==.Deyndel:BAABLgAECn8WAAIDAAYJDgbvvwAHAQADAAYJDgbvvwAHAQAAAA==.',
Di='Divinesyn:BAAALgAECggJEgAAAA==.',
Dj='Djtaki:BAACLgAFFH8GAAIGAAMJCBCJHgDuAAAGAAMJCBCJHgDuAAAuAAQKfyMAAwYABwkiF9McABgCAAYABwkiF9McABgCAAcAAQlcD2khADcAAAAA.',
Do='Dobs:BAABLgAECn8kAAIRAAkJ/BkFCAA5AgARAAkJ/BkFCAA5AgAAAA==.Dogwater:BAACLgAFFH8HAAIdAAUJrBLRDgA6AQAdAAUJrBLRDgA6AQAuAAQKfy0AAx0ACAlFIY8EANACAB0ACAlFIY8EANACABIAAQk5DIGMAC8AAAAA.Domimpatrix:BAAALgADCgYJBgAAAA==.Doncarlos:BAABLgAECn8iAAIKAAgJdyGEEACkAgAKAAgJdyGEEACkAgAAAA==.Dopey:BAAALgAECgIJAgAAAA==.Dorn:BAAALgADCgQJBAAAAA==.Dotsonly:BAAALgAECgcJEwAAAA==.Dotty:BAAALgAECgIJBAAAAA==.Downbeatxo:BAECLgAFFH8aAAMUAAgJaRVuBQA4AgAUAAgJaRVuBQA4AgAiAAEJSBXWFABVAAAuAAQKfy0AAxQACQknJDsLACEDABQACQknJDsLACEDACIAAgnUHDROAIMAAAAA.',
Dr='Dracow:BAAALgADCgkJFAABLgAECggJJgAhAHkZAA==.Dragonflash:BAABLgAECn8tAAMKAAgJQx+eFgB3AgAKAAgJQx+eFgB3AgASAAEJAAC1nAAEAAAAAA==.Drippie:BAAALgADCgUJBwAAAA==.Droodormi:BAAALgAECgIJAgAAAA==.',
Du='Dubdred:BAAALgAECgMJCAABLgAECggJLQAgANcYAA==.Duberrok:BAABLgAECn8tAAMgAAgJ1xiIFwAlAgAgAAgJ1xiIFwAlAgADAAMJxQ1N+wCdAAAAAA==.Dunes:BAAALgAECgQJBAAAAA==.Dunidane:BAAALgADCgYJBgAAAA==.Durk:BAAALgAECgUJCQAAAA==.Durkk:BAAALgAECgUJBQAAAA==.',
Dw='Dwarfskin:BAAALgADCgQJBQAAAA==.Dwín:BAABLgAECn8jAAMKAAkJRQazZgBIAQAKAAkJRQazZgBIAQASAAEJ+QCPmgAYAAAAAA==.',
Ea='Earthstalker:BAABLgAECn8VAAILAAcJVSWtCgDjAgALAAcJVSWtCgDjAgAAAA==.',
El='Elasper:BAAALgAECgUJEQAAAA==.Eleathis:BAAALgAECgMJBAAAAA==.',
Em='Emelianas:BAAALgADCgkJCQAAAA==.Emotionalism:BAAALgAECgYJBgAAAA==.Emäcs:BAAALgADCgIJAgAAAA==.',
En='Enjin:BAABLgAECn8uAAMdAAkJxiAWBwCVAgAdAAkJxiAWBwCVAgAKAAEJVgQBCQEuAAAAAA==.Enragedbeef:BAABLgAECn8WAAMDAAYJFRLAjABiAQADAAYJFRLAjABiAQAgAAQJ1g05awDNAAABLgAFFAQJBwAUAAMHAA==.Entheogen:BAABLgAECn8ZAAIcAAgJLxqbFQAPAgAcAAgJLxqbFQAPAgAAAA==.',
Ep='Eps:BAAALgADCgUJBQAAAA==.',
Er='Erahlon:BAAALgADCgkJHQAAAA==.Eralak:BAAALgADCgIJAgAAAA==.Ereckshaun:BAAALgADCgQJAgAAAA==.Eree:BAAALgAECgMJBQAAAA==.Eremin:BAAALgADCgUJBQAAAA==.Erinora:BAAALgAECgEJAQABLgAFFAYJEQAWABUVAA==.Ermoonsia:BAAALgADCgcJDAAAAA==.Erolas:BAAALgAECgQJBAAAAA==.',
Ev='Evanessance:BAAALgADCggJFQAAAA==.Evoka:BAABLgAECn8ZAAIjAAgJnQahGAAkAQAjAAgJnQahGAAkAQAAAA==.Evopunkt:BAAALgAECgcJDAAAAA==.',
Fa='Faavimonk:BAABLgAECn8XAAMaAAYJ3RZbMQBgAQAaAAYJgRNbMQBgAQAkAAEJhx/gagBWAAAAAA==.Fallendevout:BAAALgADCgkJFgAAAA==.Fallendots:BAAALgADCgUJCQAAAA==.Fallenseer:BAABLgAECn8XAAIcAAYJbBo2OwBhAQAcAAYJbBo2OwBhAQAAAA==.Fallentroll:BAACLgAFFH8OAAIIAAQJdgx1WQAcAQAIAAQJdgx1WQAcAQAuAAQKfxkAAggACAmFFnhKAMABAAgACAmFFnhKAMABAAAA.Faress:BAAALgAECgEJAQAAAA==.Fatman:BAAALgAECgcJEQAAAA==.Faydark:BAABLgAECn8VAAMVAAUJSxawEAAgAQAVAAUJSxawEAAgAQAUAAQJLgvpyQCcAAAAAA==.Fayia:BAAALgAECgQJBQAAAA==.Fayye:BAABLgAECn8cAAIgAAgJlw4pKgCWAQAgAAgJlw4pKgCWAQAAAA==.',
Fe='Feliandril:BAAALgAECgEJAQAAAA==.Fellin:BAABLgAECn8uAAMKAAkJKwk5SQCZAQAKAAkJawg5SQCZAQASAAgJ2AVMEwADAQAAAA==.Femto:BAACLgAFFH8SAAIIAAMJPSXzIAAVAQAIAAMJPSXzIAAVAQAuAAQKf0EAAggACQkZJYkEAEgDAAgACQkZJYkEAEgDAAAA.',
Fi='Fiestyrae:BAAALgAECgEJAgAAAA==.Fintrollz:BAAALgAECgYJCwAAAA==.Fiorina:BAAALgAECgEJAQABLgAECggJMgAJAHUYAA==.Fireburd:BAAALgADCgYJCgAAAA==.Firèflyjd:BAABLgAECn8gAAQVAAcJJCKpBAAaAgAVAAYJ6R+pBAAaAgAUAAUJUyDQQwC4AQAiAAQJBh7IGgCvAAAAAA==.Fishersam:BAAALgADCgYJBgAAAA==.Fishy:BAAALgADCgkJDwAAAA==.',
Fl='Flintzombie:BAAALgADCgkJCgABLgAECggJMgAeAM0XAA==.Floatpass:BAACLgAFFH8LAAIOAAMJLxk7XAACAQAOAAMJLxk7XAACAQAuAAQKfy8AAg4ACAkzIdkdAI8CAA4ACAkzIdkdAI8CAAAA.Floweranjel:BAAALgADCgYJEAAAAA==.Fluffymyone:BAABLgAECn8vAAIOAAgJkwKCvwDtAAAOAAgJkwKCvwDtAAAAAA==.',
Fo='Foghat:BAAALgADCgcJCgAAAA==.Fongsiyuk:BAABLgAECn8XAAIaAAYJRBGHNwD4AAAaAAYJRBGHNwD4AAAAAA==.Foxhammer:BAAALgADCgkJEAAAAA==.',
Fr='Fredwick:BAAALgADCgUJBQABLgAECgQJBAACAAAAAA==.Freezeberry:BAAALgAECgEJAwAAAA==.Friede:BAAALgAFFAIJBAABLgAFFAMJEgAIAD0lAA==.Frizz:BAAALgAECgYJDAAAAA==.Froey:BAAALgADCgQJBAAAAA==.Froeyglaive:BAAALgAECgQJCAAAAA==.',
Fu='Funeemonkee:BAAALgAECgIJAgABLgAECgkJMQAIAAUhAA==.Furlog:BAAALgADCgYJBwAAAA==.Fuzz:BAAALgADCgIJAgAAAA==.Fuzzymonk:BAAALgAECgcJDAAAAA==.Fuzzytotems:BAABLgAFFH8NAAILAAUJdBlDEwCCAQALAAUJdBlDEwCCAQAAAA==.',
['Fá']='Fáavi:BAAALgAECgUJBQABLgAECgkJFwAaAN0WAA==.',
Ga='Gabagooly:BAAALgAECgMJAwAAAA==.Gali:BAACLgAFFH8NAAMKAAQJWBDsDQDoAAAKAAQJNw/sDQDoAAASAAMJNgaHGgCUAAAuAAQKfzQABAoACQmaG3IOAMgCAAoACQmHG3IOAMgCABIACAlbFB86AHkBAB0AAQkCFsxQAD8AAAAA.Galiagante:BAAALgADCgcJFgAAAA==.Galiashammy:BAAALgADCgUJBQABLgADCgcJFgACAAAAAA==.Gallynna:BAABLgAECn84AAQVAAkJmhhIBAAmAgAVAAgJoRpIBAAmAgAUAAYJWhCtZQBcAQAiAAYJFRGnNADkAAAAAA==.Galorfax:BAABLgAECn8tAAIRAAgJuhwMCAA4AgARAAgJuhwMCAA4AgAAAA==.Galorfox:BAAALgADCgUJBQAAAA==.Galushi:BAAALgAECgQJBAAAAA==.Gamervato:BAAALgAECgIJAgAAAA==.Gannondalf:BAAALgADCgUJBQABLgAECggJMgAeAM0XAA==.Garlic:BAAALgAECgMJBgAAAA==.Garm:BAABLgAECn8fAAIKAAcJzCGVIQA1AgAKAAcJzCGVIQA1AgAAAA==.',
Ge='Gelinea:BAAALgAECgcJEgAAAA==.Genovese:BAABLgAECn8ZAAMIAAkJ8gkMhwAwAQAIAAgJnwkMhwAwAQATAAcJTgnJGQC3AAAAAA==.Gerardbutler:BAAALgADCgkJCQAAAA==.Geyboy:BAAALgAECgUJBwAAAA==.',
Gi='Gilagain:BAAALgAECgIJAgAAAA==.Gilgameshx:BAAALgADCgIJAgAAAA==.Gilgaroth:BAABLgAECn8lAAMGAAgJExytFgC/AQAGAAcJgx+tFgC/AQAHAAMJoA3zFQCjAAAAAA==.Girdlin:BAAALgADCgcJEgAAAA==.Girlslove:BAABLgAECn8UAAIFAAkJ9B62BwDGAgAFAAkJ9B62BwDGAgABLgAFFAUJBwAdAKwSAA==.',
Gl='Glaucoma:BAABLgAECn8WAAIhAAgJ0BQ1PQCyAQAhAAgJ0BQ1PQCyAQAAAA==.',
Go='Gobo:BAAALgAECgMJAwABLgAECgkJIQAFAHMSAA==.Goochpooch:BAAALgAECgUJBwAAAA==.Gorendish:BAAALgADCggJBwAAAA==.Gotideath:BAAALgAECgYJCwABLgAECggJFAAhAF4RAA==.Goude:BAAALgADCgkJCQAAAA==.',
Gr='Graevus:BAABLgAECn8xAAMfAAkJ2hYpIQA7AgAfAAkJ2hYpIQA7AgAJAAcJMBAXLQBAAQAAAA==.Graku:BAAALgAECgkJEQAAAA==.Graysonn:BAAALgAECgEJAQAAAA==.Greyheart:BAAALgADCgUJBQAAAA==.Grimmora:BAAALgADCgYJDwAAAA==.Grëybeard:BAACLgAFFH8FAAIQAAMJgAwxGgDKAAAQAAMJgAwxGgDKAAAuAAQKfzQAAhAACQlJHjQEALUCABAACQlJHjQEALUCAAAA.',
Gu='Gundrakk:BAACLgAFFH8RAAIfAAQJMhLQIgAVAQAfAAQJMhLQIgAVAQAuAAQKfzsAAx8ACQn/ItMCAIYDAB8ACQn/ItMCAIYDAAkACAnYDHEqAFABAAAA.Gunnr:BAAALgAECgQJBAABLgAECggJCgACAAAAAA==.Gunthorian:BAABLgAECn81AAQlAAgJMBzVCAAWAgAlAAgJ2hvVCAAWAgADAAgJdw9vagB6AQAgAAYJgBHmTABFAQAAAA==.Gurusham:BAAALgAECgEJAwAAAA==.',
Ha='Hame:BAAALgADCgMJAwAAAA==.Hamme:BAAALgADCgEJAQAAAA==.Handsomemonk:BAABLgAECn8rAAQNAAgJBRmkHQDqAQANAAcJCBqkHQDqAQAkAAcJPxTrSQAbAQAaAAUJuRBvXgBsAAAAAA==.Hangvhul:BAABLgAECn8hAAIPAAkJ0Q53DgCQAQAPAAkJ0Q53DgCQAQAAAA==.Hansi:BAAALgAFFAIJBAAAAA==.Harkonnen:BAABLgAECn85AAQUAAgJvg98WAB+AQAUAAgJYQ98WAB+AQAiAAEJ+RO4cQA0AAAVAAEJ8gVBMwAsAAAAAA==.',
He='Healmme:BAAALgAECgUJBQAAAA==.Heart:BAAALgAECgMJCAABLgAECgQJCgACAAAAAA==.Hearth:BAAALgAECgEJAQAAAA==.Hectic:BAAALgADCgMJAwABLgAECggJHQAgAJgbAA==.Heid:BAAALgAECgQJBAAAAA==.Helianna:BAAALgAFFAMJAwABLgAFFAYJGAAKAAcbAA==.Helldozer:BAAALgAECgUJEAAAAA==.Hellsong:BAAALgADCgUJBQAAAA==.',
Hi='Himejoshi:BAACLgAFFH8JAAImAAQJsSDBAgB3AQAmAAQJsSDBAgB3AQAuAAQKfyMAAyYACAmOJGUBAFwDACYACAmOJGUBAFwDABEABwnsHuIFAHUCAAEuAAUUBQkHAB0ArBIA.Hirys:BAACLgAFFH8JAAIGAAMJ/xraGQAUAQAGAAMJ/xraGQAUAQAuAAQKfxoAAgYACQkgHiULAE4CAAYACQkgHiULAE4CAAAA.',
Ho='Holybanana:BAABLgAECn8hAAIgAAgJsyIyCADkAgAgAAgJsyIyCADkAgAAAA==.Holymerble:BAAALgAECgEJAQABLgAECgcJDwACAAAAAA==.Holyramen:BAAALgADCgcJBwAAAA==.Horsewing:BAAALgAECgYJEAAAAA==.Hotdoggin:BAAALgAECgUJBgAAAA==.Hotmerble:BAAALgAECgcJDwAAAA==.Hotshotzz:BAAALgAECgQJBgABLgAFFAYJEAAOAD8PAA==.Hotstreak:BAACLgAFFH8QAAIOAAYJPw96JgCJAQAOAAYJPw96JgCJAQAuAAQKfx4AAg4ACQk7HcsXALACAA4ACQk7HcsXALACAAAA.',
Hu='Hunthamme:BAAALgAECgYJBwAAAA==.Huntsmedown:BAAALgAECgMJBQAAAA==.',
Hy='Hyjali:BAAALgADCgEJAQAAAA==.',
['Há']='Háldrin:BAACLgAFFH8YAAQKAAYJBxuECwAGAQAdAAUJcBeFDABKAQAKAAUJUQ6ECwAGAQASAAMJHhWgHQBtAAAuAAQKfyAABBIACAkpHFccAEUCABIACAkCGlccAEUCAB0ABglWIT0UAOkBAAoABAnUItFtADcBAAAA.',
['Hä']='Härmacist:BAAALgAECgUJBQAAAA==.',
Ia='Iamcow:BAAALgAECgUJCQAAAA==.',
Il='Illexi:BAAALgADCgYJBgAAAA==.Ilthunis:BAAALgADCgcJEAAAAA==.',
Im='Imadruîd:BAAALgAECgYJCgAAAA==.Imbue:BAABLgAECn8iAAInAAkJCB5WBABUAgAnAAkJCB5WBABUAgAAAA==.Immortals:BAAALgAECgQJBQAAAA==.Imthatguyy:BAAALgAECgMJAwABLgAECgYJBwACAAAAAA==.',
In='Innil:BAACLgAFFH8FAAMEAAMJiRScIgDoAAAEAAMJiRScIgDoAAAWAAEJ0wajLgBFAAAuAAQKfxQABBkABwm7F9I0AGsBABkABgmNGdI0AGsBABYABwlRFZY1ABkBAAQAAgloCTZkADEAAAAA.',
Ip='Ipunch:BAAALgAECgQJDAABLgAECgYJBwACAAAAAA==.',
Is='Isimiel:BAAALgADCgQJBAAAAA==.',
It='Itahchii:BAAALgADCgUJBQABLgAECgQJBAACAAAAAA==.Itzapazz:BAAALgADCgkJDQAAAA==.',
Iv='Ivyrahh:BAAALgADCgIJAgAAAA==.',
Ja='Jaesa:BAAALgADCgEJAQAAAA==.Jardah:BAAALgAECgQJBQABLgAECgYJBwACAAAAAA==.Jaycee:BAAALgADCgQJBAAAAA==.',
Je='Jessicks:BAAALgAECgEJAQABLgAECgUJCQACAAAAAA==.Jessiks:BAAALgAECgEJAQAAAA==.Jessix:BAAALgAECgUJCQAAAA==.Jetlisa:BAAALgADCgcJBwAAAA==.Jeybi:BAAALgAFFAIJAgAAAA==.Jezebel:BAABLgAECn8qAAMUAAgJKhmdLAAPAgAUAAgJKhmdLAAPAgAiAAEJmASuOQAmAAAAAA==.',
Ji='Jiaoe:BAAALgADCgQJBAAAAA==.Jinxing:BAAALgAECgMJAwAAAA==.Jinze:BAAALgAECgQJBQAAAA==.Jirito:BAAALgADCgcJBwABLgAECgkJGgAfALQNAA==.Jirto:BAABLgAECn8aAAIfAAkJtA3YSAB/AQAfAAkJtA3YSAB/AQAAAA==.',
Jo='Jomadead:BAABLgAECn8jAAIMAAkJ2RuVCQBPAgAMAAkJ2RuVCQBPAgABLgAFFAcJJAALAF0YAA==.Jomadh:BAABLgAFFH8GAAIhAAUJtwkDPgAEAQAhAAUJtwkDPgAEAQAAAA==.Jomadin:BAAALgAECgEJAQABLgAFFAcJJAALAF0YAA==.Jomage:BAAALgADCgcJBwABLgAFFAcJJAALAF0YAA==.Jomar:BAAALgAECgcJDgAAAA==.Jomas:BAACLgAFFH8kAAMLAAcJXRjFAgBcAgALAAcJXRjFAgBcAgAcAAEJWwUOQwA8AAAuAAQKfy8AAwsACQl2IucHAPYCAAsACQl2IucHAPYCABwABQkLIL0xAJUBAAAA.',
Ju='Jubbjubb:BAACLgAFFH8OAAIOAAQJoQ0IUgAkAQAOAAQJoQ0IUgAkAQAuAAQKfzAAAg4ACQlDIMAhAHsCAA4ACQlDIMAhAHsCAAAA.Judera:BAABLgAECn8iAAIDAAgJ6RdkTgC+AQADAAgJ6RdkTgC+AQAAAA==.Jugful:BAAALgAECgEJAQAAAA==.Juicemoose:BAABLgAECn8pAAMfAAkJSAu+QABrAQAfAAkJSAu+QABrAQAJAAIJFAWzfwAnAAAAAA==.Juicybooty:BAAALgADCgUJBQAAAA==.Justokelf:BAABLgAECn8oAAIhAAgJcSFOEgCTAgAhAAgJcSFOEgCTAgAAAA==.',
Jw='Jwarr:BAAALgADCgEJAQAAAA==.',
Ka='Kagura:BAAALgADCgcJBwAAAA==.Kaiden:BAAALgADCgkJGwAAAA==.Kaing:BAABLgAECn8fAAMYAAYJ8w4YRgAEAQAYAAYJ8w4YRgAEAQAeAAEJsguMTQAgAAAAAA==.Kainlithia:BAAALgAFFAEJAgAAAA==.Kaladen:BAAALgAECgQJBwAAAA==.Kalindica:BAAALgADCgYJBgAAAA==.Kalysti:BAAALgAECggJMgAAAQ==.Kandee:BAAALgAECgYJEQAAAA==.Karkonas:BAAALgADCgcJCAABLgAFFAEJAwACAAAAAA==.Karliahdark:BAAALgAECgMJBAAAAA==.Karolg:BAAALgAECgQJBAAAAA==.Karuli:BAAALgADCgkJIgAAAA==.Karvis:BAAALgAECgUJDgAAAA==.Kasuri:BAAALgAECgEJAwAAAA==.Katostrafic:BAABLgAECn8fAAIEAAgJUh2LCQCvAgAEAAgJUh2LCQCvAgAAAA==.Katotonic:BAAALgAECgEJAQAAAA==.Kaylieè:BAAALgADCgEJAQABLgAECgcJIAAVACQiAA==.Kazemage:BAABLgAECn8lAAMBAAgJ8hRxAwDDAQABAAgJ8hRxAwDDAQAOAAEJKQK1TgEjAAAAAA==.Kazesun:BAAALgAECgYJBwAAAA==.',
Ke='Kessarian:BAAALgADCgkJCQAAAA==.Kevais:BAAALgAECgYJCAAAAA==.',
Kh='Khromscarin:BAACLgAFFH8JAAInAAMJ+CLbAgAqAQAnAAMJ+CLbAgAqAQAuAAQKfz0AAicACQkCI9UAACcDACcACQkCI9UAACcDAAAA.',
Ki='Kiaradarkpaw:BAAALgAECgEJAgAAAA==.Kielli:BAAALgADCgEJAQAAAA==.Killboi:BAAALgAECgUJCwAAAA==.Killem:BAAALgADCgQJBAAAAA==.Killidan:BAACLgAFFH8RAAIhAAUJlBfqLAA0AQAhAAUJlBfqLAA0AQAuAAQKfxsAAiEACQlOIoURAPICACEACQlOIoURAPICAAAA.Kimberllynn:BAAALgAECgcJBwAAAA==.Kiridus:BAABLgAECn8yAAMJAAgJdRjYGADYAQAJAAgJdRjYGADYAQAfAAEJoQT54QAjAAAAAA==.Kirklees:BAAALgAECgQJCAAAAA==.',
Kl='Klaudiuss:BAAALgAECgQJBAAAAA==.',
Kn='Knackers:BAAALgADCggJDQAAAA==.',
Ko='Kodama:BAABLgAECn82AAIcAAgJEBGbLwBUAQAcAAgJEBGbLwBUAQAAAA==.Koi:BAAALgADCgkJEAABLgAECgkJOQAhAAElAA==.Kookiemon:BAAALgAECgQJBAAAAA==.Kookiesplz:BAAALgADCgkJHQAAAA==.Kopili:BAAALgAECgQJEwAAAA==.Koryn:BAABLgAECn8fAAIWAAcJbw9MLQBFAQAWAAcJbw9MLQBFAQAAAA==.Kotz:BAAALgAECggJEAAAAA==.',
Kr='Kratina:BAAALgADCgEJAQAAAA==.Kreshtharion:BAAALgADCgYJBgAAAA==.Krunthe:BAAALgAECgQJBAAAAA==.Kryxis:BAAALgAECgcJDgAAAA==.',
Ku='Kunpochiken:BAAALgAECgQJCQABLgAECggJHwAEAFIdAA==.',
Ky='Kyanna:BAAALgAECgYJEQAAAA==.Kyllan:BAAALgADCgIJAgAAAA==.',
La='Lacrymos:BAABLgAECn8xAAInAAkJrBpyBABPAgAnAAkJrBpyBABPAgAAAA==.Lader:BAAALgAECgkJEAAAAA==.Larril:BAAALgADCgYJBwAAAA==.Laurebeth:BAAALgADCgkJDQAAAA==.Laxinmedium:BAAALgAECgQJBAAAAA==.Laxinstalker:BAAALgADCgUJBQABLgAECgQJBAACAAAAAA==.',
Le='Leenei:BAAALgAECgUJCQAAAA==.Leesina:BAAALgAECgQJBwAAAA==.Lenlaar:BAAALgAECgYJEQAAAA==.Lesavatar:BAAALgADCgUJBQABLgAECgkJJQAIAEsjAA==.Levande:BAABLgAECn8bAAMZAAgJYR3sEgBIAgAZAAgJYR3sEgBIAgAEAAUJ/Q2YMQAUAQAAAA==.',
Li='Lid:BAAALgADCgMJAwAAAA==.Lifeblume:BAAALgADCgYJBgAAAA==.Lighttickle:BAAALgADCgMJAwAAAA==.Liling:BAAALgADCgEJAgABLgAECgYJCgACAAAAAA==.Lilithandria:BAABLgAECn8mAAMhAAgJeRkyMgDdAQAhAAgJJRgyMgDdAQAbAAQJDBl/IgApAQAAAA==.Lilletth:BAAALgADCgUJBQAAAA==.Lilyola:BAABLgAECn8YAAIBAAYJggZACQDMAAABAAYJggZACQDMAAAAAA==.Limabeanjr:BAAALgADCggJCAAAAA==.Linamar:BAAALgADCgkJQgAAAA==.Lisan:BAAALgAECgQJBAAAAA==.',
Lo='Loaq:BAACLgAFFH8JAAIEAAMJJA5PJQDUAAAEAAMJJA5PJQDUAAAuAAQKfzMAAgQACQmiHdUIAK8CAAQACQmiHdUIAK8CAAAA.Lockzrockz:BAAALgAFFAIJAwAAAA==.Longbottom:BAAALgAECgYJBgAAAA==.Lorbert:BAAALgAECgQJCAABLgAECgcJIAAYAOoXAA==.',
Lu='Luxæterna:BAABLgAECn8+AAIDAAkJqByaHQB2AgADAAkJqByaHQB2AgAAAA==.',
Ly='Lystrasza:BAABLgAECn8dAAIXAAkJRRd+BAANAgAXAAkJRRd+BAANAgAAAA==.Lyte:BAAALgADCgYJEAAAAA==.',
['Lí']='Líllìth:BAAALgADCgYJBgAAAA==.',
Ma='Madjekyll:BAAALgAECgEJAwABLgAECggJLAAYALQlAA==.Magnamalo:BAAALgAECgcJCgABLgAECggJCgACAAAAAA==.Magus:BAAALgAECgIJBQAAAA==.Maikeru:BAABLgAECn8oAAIoAAcJnh9hBAAVAgAoAAcJnh9hBAAVAgAAAA==.Maizy:BAAALgADCgIJAgAAAA==.Malduku:BAAALgADCgYJBgAAAA==.Malemenas:BAAALgADCgkJJgAAAA==.Malice:BAABLgAECn8sAAMVAAgJEiFlAQDfAgAVAAgJEiFlAQDfAgAUAAMJRwu6zACXAAAAAA==.Mandwandos:BAAALgAECgkJEQAAAA==.Maraliss:BAABLgAECn8fAAImAAcJ0QmPGgD9AAAmAAcJ0QmPGgD9AAAAAA==.Marjon:BAABLgAECn8jAAIiAAcJTw4gEAAVAQAiAAcJTw4gEAAVAQAAAA==.Maroonfive:BAAALgAECgEJAgAAAA==.Marrash:BAAALgADCgcJBgAAAA==.Masashii:BAAALgADCgQJBAABLgAECgkJOQAhAAElAA==.Mastatea:BAAALgADCggJCgAAAA==.Matamoros:BAAALgADCgcJCAAAAA==.Maugrimm:BAAALgAECgYJBwAAAA==.Maxn:BAAALgAECgEJAQAAAA==.Maxrox:BAAALgAECgQJBAAAAA==.Mayalodu:BAAALgAECgQJEQAAAA==.',
Me='Mekkanna:BAAALgAECgMJAwAAAA==.Melaunis:BAAALgAECgcJEAAAAA==.Mellwynn:BAAALgADCgkJAwAAAA==.Mellínna:BAAALgADCgYJCwAAAA==.Meora:BAAALgAECgcJCQABLgAFFAUJHQAeAP8bAA==.Meowelf:BAAALgADCgUJBQAAAA==.Meowow:BAABLgAECn8WAAIOAAcJegj0twD5AAAOAAcJegj0twD5AAAAAA==.Meowzer:BAAALgADCgEJAQABLgAFFAQJBwAUAAMHAA==.Merks:BAABLgAECn8UAAMDAAcJFgdkwgDhAAADAAcJoAZkwgDhAAAlAAQJrwZAMAB3AAAAAA==.Metas:BAAALgAECgcJDQABLgAFFAUJHQAeAP8bAA==.Meteora:BAACLgAFFH8dAAIeAAUJ/xvLCgBFAQAeAAUJ/xvLCgBFAQAuAAQKfyMAAh4ACQmKHp8IAJYCAB4ACQmKHp8IAJYCAAAA.Metero:BAAALgAECgkJCQABLgAFFAUJHQAeAP8bAA==.',
Mh='Mhithrha:BAABLgAECn8hAAIJAAkJjhXEFwDjAQAJAAkJjhXEFwDjAQAAAA==.',
Mi='Mideel:BAAALgAECgYJEQAAAA==.Migal:BAAALgADCgYJBgABLgAECggJJgAhAHkZAA==.Migolbearcow:BAABLgAECn86AAIRAAgJaR0yBwBPAgARAAgJaR0yBwBPAgAAAA==.Miinx:BAACLgAFFH8LAAIRAAQJ1BtcCAAcAQARAAQJ1BtcCAAcAQAuAAQKfxoAAhEACAmHICwFAIkCABEACAmHICwFAIkCAAAA.Minervamon:BAAALgADCgMJAwAAAA==.Minotauren:BAAALgAECgcJEgAAAA==.Missed:BAABLgAECn8cAAIDAAgJIyPdHgBvAgADAAgJIyPdHgBvAgABLgAECgkJHgANAO0cAA==.Missedshaped:BAAALgAECgIJAgABLgAECgkJHgANAO0cAA==.Missedweaver:BAABLgAECn8eAAMNAAkJ7Ry+CQDKAgANAAkJ7Ry+CQDKAgAaAAEJhBS1eAA8AAAAAA==.Misseed:BAAALgADCgYJBgABLgAECgkJHgANAO0cAA==.Missrae:BAAALgADCgkJDwAAAA==.Mistyelliott:BAAALgADCgcJBwABLgAECgkJQAAfAJUeAA==.Miyuni:BAAALgADCgMJAwAAAA==.',
Mk='Mk:BAEBLgAECn8VAAIoAAgJnRalBQDhAQAoAAgJnRalBQDhAQABLgAECggJOwAaAGsjAA==.',
Ml='Mlglock:BAABLgAECn8XAAIUAAkJ9Bs+IgCMAgAUAAkJ9Bs+IgCMAgAAAA==.',
Mo='Mongocrush:BAAALgAECgIJAgAAAA==.Monyshot:BAAALgADCgEJAQAAAA==.Moocifur:BAAALgADCgkJEgAAAA==.Moonbeary:BAAALgAECgcJCAAAAA==.Mooniè:BAABLgAECn8gAAIOAAcJxgSBuAD4AAAOAAcJxgSBuAD4AAAAAA==.Moosensquirl:BAAALgADCgcJBwAAAA==.Moosenuts:BAAALgADCgkJAwAAAA==.Morzhul:BAAALgAECgUJBgAAAA==.Moxxii:BAABLgAECn8WAAMMAAgJlhz2DwANAgAMAAYJmiD2DwANAgAIAAMJjg9V5wCxAAAAAA==.',
Mu='Muradigme:BAAALgAECgcJDgAAAA==.Mushufasa:BAAALgAECgEJAQAAAA==.Mutilusgore:BAABLgAECn8yAAIeAAgJzReWDwDGAQAeAAgJzReWDwDGAQAAAA==.',
My='Myrium:BAAALgAECgQJCAAAAA==.Myshella:BAAALgAECgcJEQAAAA==.Myylus:BAAALgADCggJEgAAAA==.',
['Mö']='Mökes:BAACLgAFFH8WAAIiAAQJYCPHAQCdAQAiAAQJYCPHAQCdAQAuAAQKfyMAAiIACAlDI1UBABkDACIACAlDI1UBABkDAAAA.',
Na='Naijin:BAAALgADCgEJAQABLgAECgYJCgACAAAAAA==.Nasana:BAAALgADCgQJBAAAAA==.Navarra:BAAALgADCgEJAQAAAA==.Nawzero:BAAALgAECggJCQAAAA==.Nax:BAAALgAECgEJBQAAAA==.Nazagos:BAAALgAECgcJCQABLgAECgkJJQAKAPckAA==.Nazeiro:BAABLgAECn8RAAIhAAYJShDNeAA8AQAhAAYJShDNeAA8AQAAAA==.Nazzersaurus:BAABLgAECn8mAAIfAAgJ0BtVFgByAgAfAAgJ0BtVFgByAgAAAA==.',
Ne='Negies:BAAALgADCgYJBgAAAA==.Nekestinea:BAAALgADCgIJAgAAAA==.Nekomata:BAABLgAECn8cAAIJAAgJbRf9GQDOAQAJAAgJbRf9GQDOAQAAAA==.Nekosmasta:BAAALgADCggJCAAAAA==.Neodin:BAAALgADCgkJQgAAAA==.Newhamme:BAAALgAECggJDgAAAA==.',
Ni='Nightjewel:BAAALgAECgQJBAAAAA==.Nightstalkër:BAAALgADCgcJBwABLgAECgkJEwACAAAAAA==.',
No='Noctevera:BAAALgADCgkJEQAAAA==.Noggs:BAAALgAECgEJAQAAAA==.Nokawa:BAAALgADCgYJBgAAAA==.Nokkas:BAAALgAECgcJCwAAAA==.Novadisc:BAAALgADCggJCAAAAA==.',
Nu='Nuali:BAAALgADCgkJEQABLgAECgkJIgAZAIkYAA==.Numbers:BAACLgAFFH8IAAIgAAQJcRuUFABOAQAgAAQJcRuUFABOAQAuAAQKfx0AAiAACQl9HrEIAOQCACAACQl9HrEIAOQCAAAA.Numì:BAAALgAECgQJBAAAAA==.',
['Nê']='Nêrtt:BAABLgAECn9BAAQXAAgJ5x7xBQCYAgAXAAcJkh/xBQCYAgAjAAgJ/RneBwBVAgAFAAUJACNfKQB5AQAAAA==.',
Oc='Oche:BAAALgADCgcJEwABLgAECggJJAAOAJ4MAA==.',
Ok='Oketra:BAAALgADCgUJBQAAAA==.',
Ol='Olm:BAAALgAECgEJAQAAAA==.',
Om='Omniia:BAAALgAECgMJAwAAAA==.',
On='Onedog:BAAALgAECgEJAQAAAA==.Ontera:BAAALgAECgYJCgAAAA==.',
Or='Orala:BAABLgAECn8lAAIWAAkJRBQSFgD1AQAWAAkJRBQSFgD1AQAAAA==.Orlaya:BAAALgAECgEJAQAAAA==.Orý:BAABLgAECn82AAIcAAkJPh/1CgCNAgAcAAkJPh/1CgCNAgAAAA==.',
Os='Oslatem:BAABLgAECn8XAAMOAAYJ2hAepQAYAQAOAAYJnw8epQAYAQABAAIJqg+2DABxAAAAAA==.',
Ot='Ottrekker:BAAALgADCgIJAgABLgAECggJEAACAAAAAA==.',
Ov='Overlie:BAAALgADCgUJBQAAAA==.',
Ox='Oxosorrel:BAAALgAECgEJAQAAAA==.',
Pa='Paladan:BAACLgAFFH8PAAMDAAQJjRvkIQBQAQADAAQJjRvkIQBQAQAlAAEJ+xNwBwA9AAAuAAQKfxoAAwMACQksImgLADMDAAMACQnwIWgLADMDACUABwkLIeAIAEgCAAAA.Paladeez:BAAALgAECgQJBAAAAA==.Pallyana:BAAALgAECgQJBQAAAA==.Palyboye:BAAALgADCgQJBAAAAA==.Pamorlin:BAAALgAECgEJBAAAAA==.Pandaemoni:BAAALgAECggJCgAAAA==.Pandamonea:BAAALgADCggJDgABLgAECggJCgACAAAAAA==.Pandamonium:BAAALgADCgYJCQABLgAECggJCgACAAAAAA==.Pandapunkt:BAAALgAECgYJDwAAAA==.Pandragon:BAAALgAECgIJAgABLgAECggJCgACAAAAAA==.Parallax:BAAALgAECgYJDgAAAA==.Parishealton:BAABLgAECn9AAAIfAAkJlR7xCAANAwAfAAkJlR7xCAANAwAAAA==.Pastybeard:BAABLgAECn8yAAMVAAkJuSSVAAAXAwAVAAkJuSSVAAAXAwAUAAkJGhqsHwBOAgAAAA==.Pazzuzu:BAAALgAFFAEJAQAAAA==.',
Pe='Penjamin:BAAALgAECgYJDQAAAA==.Pewnani:BAAALgADCgMJAwAAAA==.',
Ph='Phaestos:BAAALgAECgMJCgABLgAECggJMgAJAHUYAA==.',
Pi='Pinkburrito:BAAALgADCgEJAQAAAA==.',
Pl='Planetes:BAAALgAECgIJBAAAAA==.',
Po='Pontar:BAAALgAECgYJBgAAAA==.Pordobel:BAAALgADCgEJAQAAAA==.Portalnugget:BAAALgAECgEJAQABLgAFFAQJEQAfADISAA==.Portalz:BAAALgADCgYJBwABLgAECgkJHgANAO0cAA==.Poulsbo:BAAALgAECgYJEQAAAA==.',
Pr='Prominence:BAABLgAECn8YAAISAAcJwBxLDQBiAQASAAcJwBxLDQBiAQAAAA==.Promisques:BAAALgADCgYJBgAAAA==.Proy:BAABLgAECn8WAAILAAcJ9xy9GABXAgALAAcJ9xy9GABXAgAAAA==.Prozak:BAABLgAECn81AAILAAgJLR4BEACnAgALAAgJLR4BEACnAgAAAA==.',
Ps='Psychofrenic:BAAALgADCgYJDgABLgAECggJLQAYAKUcAA==.',
Pu='Puhlayden:BAABLgAECn8XAAMDAAgJax7sOAA/AgADAAcJ0B7sOAA/AgAgAAcJCQqJRQBiAQAAAA==.Puredragon:BAAALgADCgYJBgAAAA==.',
['Pò']='Pòppy:BAAALgADCgcJBwAAAA==.',
Qu='Quikanez:BAABLgAECn8fAAMnAAgJJBMBCwCCAQAnAAgJJBMBCwCCAQAbAAQJ3A9USQDNAAAAAA==.Qulung:BAAALgADCgkJCQAAAA==.',
Ra='Rabyd:BAAALgAECgIJBAAAAA==.Radmane:BAAALgADCgEJAQAAAA==.Raegasm:BAAALgADCgQJBQAAAA==.Raein:BAAALgAECgYJDQAAAA==.Raithe:BAAALgADCgQJBAAAAA==.Raskela:BAABLgAECn8aAAINAAkJZRwGDgB1AgANAAkJZRwGDgB1AgAAAA==.Raskella:BAAALgAECgEJAQABLgAECgkJGgANAGUcAA==.Ratboy:BAABLgAECn8eAAMGAAgJaxl7DwCtAgAGAAgJaxl7DwCtAgAHAAEJ2g7XIAAuAAAAAA==.Ratkiss:BAAALgADCgYJBgAAAA==.',
Re='Reckhn:BAAALgAECgEJAQAAAA==.Rellidana:BAAALgAECgkJEQAAAA==.Reportyrself:BAAALgAECgYJBgAAAA==.Reprieve:BAABLgAECn8pAAMQAAgJcSD6BgBmAgAQAAgJcSD6BgBmAgAYAAQJrRKWdADoAAAAAA==.Retradormi:BAAALgADCgQJBAAAAA==.Reversal:BAAALgAECggJDwABLgAECggJLQAYAKUcAA==.Rexe:BAABLgAFFH8HAAMSAAMJYwPjFwCrAAASAAMJYwPjFwCrAAAKAAEJawGqLQBAAAAAAA==.Rexy:BAAALgAECgYJBwABLgAFFAMJBwASAGMDAA==.',
Rh='Rhane:BAABLgAECn8UAAIKAAYJ2A33gQALAQAKAAYJ2A33gQALAQAAAA==.Rhazputin:BAAALgAECgQJBQAAAA==.Rhend:BAAALgADCgcJBwAAAA==.',
Ri='Riang:BAAALgAECgEJAQAAAA==.Rickcando:BAABLgAECn8UAAIcAAQJKwYJYwCJAAAcAAQJKwYJYwCJAAAAAA==.Ricshard:BAABLgAECn8wAAMiAAkJ0hxfCwBcAQAUAAYJbxuUOQDbAQAiAAYJuRlfCwBcAQAAAA==.Ridjeckgron:BAAALgAECgQJDAAAAA==.Righteouskat:BAAALgADCgIJAgAAAA==.Rindou:BAAALgAECgQJBAABLgAECgkJIgAFAGIjAA==.Rinea:BAABLgAECn8iAAMZAAkJiRiaEwAWAgAZAAkJiRiaEwAWAgAWAAEJ6gRqZgAsAAAAAA==.Riserphenex:BAAALgAECgYJEgABLgAFFAQJEQAGAB0fAA==.Risse:BAABLgAECn8kAAIOAAgJngy9cQB5AQAOAAgJngy9cQB5AQAAAA==.Ritari:BAAALgAECgcJBgAAAA==.',
Ro='Roarkitty:BAAALgAECgUJDAAAAA==.Rocknaw:BAABLgAECn8ZAAIDAAkJrBZJQQDkAQADAAkJrBZJQQDkAQAAAA==.Rodgers:BAAALgAECggJDgABLgAFFAUJHQAeAP8bAA==.Rogaldorne:BAAALgAECgcJEAAAAA==.Rollinhotz:BAAALgAECgcJCwAAAA==.Romans:BAAALgADCgcJDwABLgAFFAQJCAAgAHEbAA==.Romina:BAAALgAECgEJAgAAAA==.Ronicary:BAAALgAECgEJAQAAAA==.Roofeed:BAAALgADCgEJAQAAAA==.Rospeteal:BAABLgAECn88AAIiAAkJQRNxBgDHAQAiAAkJQRNxBgDHAQAAAA==.',
Ru='Ruben:BAAALgADCgYJCAAAAA==.Runefnar:BAAALgADCgkJEwAAAA==.Rungar:BAAALgAECgYJBwAAAA==.',
Ry='Rydmytotem:BAAALgADCgcJEwAAAA==.Ryjin:BAAALgADCgYJBgAAAA==.Rylia:BAAALgAECgUJDQAAAA==.Ryuhari:BAABLgAECn82AAIRAAkJwCM1AQA3AwARAAkJwCM1AQA3AwAAAA==.Ryujin:BAABLgAECn8xAAMGAAgJbhrHEgDqAQAGAAgJqRnHEgDqAQAHAAYJ3gxoDwAPAQAAAA==.Ryuseki:BAAALgADCgUJBQAAAA==.',
['Ró']='Ród:BAAALgAFFAEJAQABLgAFFAYJEAAOAD8PAA==.',
Sa='Saalira:BAAALgAECgYJBgAAAA==.Sabellice:BAABLgAECn8wAAIDAAkJARJ1QQDjAQADAAkJARJ1QQDjAQAAAA==.Sadicia:BAAALgADCgIJAwAAAA==.Sakonna:BAABLgAFFH8RAAIWAAYJFRWGCACWAQAWAAYJFRWGCACWAQAAAA==.Salchydrak:BAAALgAECgQJBQABLgAFFAMJBQALAGAQAA==.Salchygood:BAAALgAECgEJAQAAAA==.Salinoria:BAABLgAECn8YAAIhAAgJ9gVLegAFAQAhAAgJ9gVLegAFAQABLgAECgkJIgAZAIkYAA==.Saltyfingers:BAAALgADCgkJEAAAAA==.Samwell:BAAALgADCgkJHwAAAA==.Sandymaw:BAAALgAECgQJBwABLgAFFAQJBwAUAAMHAA==.Saniroin:BAAALgADCgIJAgAAAA==.Sarlius:BAABLgAECn8lAAIKAAkJ9yTBAAC5AwAKAAkJ9yTBAAC5AwAAAA==.Satyrical:BAAALgAECgQJBAABLgAECgQJCgACAAAAAA==.Sausagecat:BAAALgADCgEJAQAAAA==.Savin:BAABLgAECn8ZAAIgAAcJGgjLPgAgAQAgAAcJGgjLPgAgAQAAAA==.',
Sc='Scargrimm:BAAALgAECgcJBgAAAA==.Scavenger:BAABLgAECn8UAAISAAgJIwGsKABaAAASAAgJIwGsKABaAAAAAA==.Schorsha:BAAALgAECgYJDwAAAA==.',
Se='Securityx:BAAALgADCgEJAQAAAA==.Selkamonk:BAACLgAFFH8FAAINAAIJwxPILwCGAAANAAIJwxPILwCGAAAuAAQKfzoAAw0ACQlGJTcBALwDAA0ACQlGJTcBALwDABoAAQkAAJ91AEAAAAAA.Seniorbold:BAAALgAECgQJBgAAAA==.Sentrina:BAACLgAFFH8RAAIjAAUJKBKLDwBiAQAjAAUJKBKLDwBiAQAuAAQKfywAAiMACQnPGNkPAD0CACMACQnPGNkPAD0CAAAA.Seramon:BAAALgADCgQJBAABLgAECgkJLgAdAMYgAA==.Seraph:BAAALgAECgEJAgAAAA==.Serenìty:BAAALgADCgMJAwAAAA==.Seshy:BAABLgAECn8VAAMWAAYJvwvERwDCAAAWAAYJvwvERwDCAAAEAAMJ2AWVXQBAAAABLgAFFAQJBwAUAAMHAA==.Seshymutedme:BAACLgAFFH8HAAMUAAQJAwf0UAD7AAAUAAQJoAX0UAD7AAAVAAEJawm3GgBIAAAuAAQKfyAABBQACQn/FiY8ANEBABQACAn/FiY8ANEBACIABAmQCi85ANAAABUAAgncEMksAEAAAAAA.',
Sh='Shadian:BAAALgADCgIJAgAAAA==.Shamanagins:BAAALgAECgQJBAAAAA==.Shanndril:BAAALgADCgYJBgAAAA==.Shannon:BAAALgADCgcJCAABLgAECggJHAAgAJcOAA==.Shannoon:BAABLgAECn8cAAIlAAgJ+wcWHgD1AAAlAAgJ+wcWHgD1AAAAAA==.Shekzeer:BAAALgAFFAIJAgABLgAFFAQJEQAGAB0fAA==.Shimmiiee:BAAALgAECgYJCAAAAA==.Shing:BAABLgAECn8kAAMkAAkJuyBiFADtAQAkAAkJuyBiFADtAQAaAAUJ2g0qSwDlAAAAAA==.Shiverr:BAAALgAECgYJDAAAAA==.Shocktard:BAAALgAECgkJCQABLgAECgkJJQAIAEsjAA==.Shoftìel:BAAALgADCgcJCgAAAA==.Shxt:BAAALgADCgIJAgAAAA==.',
Si='Sivrak:BAAALgADCggJBQAAAA==.',
Sk='Skizem:BAAALgADCgIJAgAAAA==.Skott:BAAALgAECgcJDgAAAA==.',
Sl='Sleepadin:BAAALgAECgcJDAAAAA==.Sleepyr:BAABLgAECn8eAAMFAAgJswtxKQBzAQAFAAgJswtxKQBzAQAjAAEJTwGzPQAOAAAAAA==.Slobkabob:BAAALgAECgEJAwAAAA==.',
Sm='Smol:BAAALgAECgMJCQAAAA==.Smolside:BAAALgADCgEJAQAAAA==.',
Sn='Snowi:BAAALgAECggJCgAAAA==.',
So='Solignis:BAACLgAFFH8rAAMYAAcJtiV8AACPAgAYAAcJtiV8AACPAgAQAAMJYSTHGwC+AAAuAAQKf0QAAxgACQmEJsYAANUDABgACQmEJsYAANUDABAAAQm1I8EyAGgAAAAA.Songs:BAAALgAECgMJAwABLgAFFAQJCAAgAHEbAA==.Soohots:BAABLgAECn8XAAIfAAgJ/Rk/GgBQAgAfAAgJ/Rk/GgBQAgAAAA==.Soular:BAAALgADCgMJAwAAAA==.',
Sp='Sparklehappy:BAABLgAECn8eAAMdAAgJlyGwCAB4AgAdAAgJlyGwCAB4AgASAAUJSxgXQgBQAQAAAA==.Spiritdurk:BAAALgADCggJDAAAAA==.Spog:BAAALgAECggJEgAAAA==.Spoghasm:BAABLgAECn8rAAIRAAkJYyT5AABHAwARAAkJYyT5AABHAwAAAA==.Sposcre:BAAALgADCgUJBQAAAA==.Spothoof:BAACLgAFFH8aAAMcAAUJ+RjHFQAyAQAcAAQJ+RjHFQAyAQAPAAEJAAAAEgAAAAAuAAQKfysAAhwACQnsH3kHAMUCABwACQnsH3kHAMUCAAAA.Sprout:BAAALgADCgQJBAAAAA==.',
St='Stalari:BAAALgAECgcJDQAAAA==.Starfoxx:BAAALgAECgEJAgAAAA==.Starshield:BAAALgAECgEJAQABLgAFFAQJBwAIANsRAA==.Stcupertino:BAABLgAECn8hAAMgAAkJ2gZPMwBdAQAgAAkJ2gZPMwBdAQADAAEJzwXbVQEoAAAAAA==.Steamedham:BAAALgAECgcJBwAAAA==.Steeljustice:BAAALgAECgYJCgAAAA==.Stellalou:BAAALgAECgEJBAAAAA==.Stormstout:BAAALgADCgIJAgAAAA==.Storri:BAABLgAECn8pAAIZAAgJwBbfFgDzAQAZAAgJwBbfFgDzAQAAAA==.Storrii:BAAALgAECgYJDAAAAA==.Stryranger:BAAALgAECgUJBQAAAA==.',
Su='Submersed:BAAALgAECgMJAwAAAA==.Suehunter:BAABLgAECn8VAAIKAAYJCgfYkADqAAAKAAYJCgfYkADqAAAAAA==.Sufferinhero:BAAALgAECgMJAwABLgAFFAMJCQAnAPgiAA==.Suturi:BAAALgADCggJCAAAAA==.Suvi:BAAALgADCgEJBQAAAA==.Suzuya:BAAALgAECgIJAgAAAA==.',
Sw='Swiftly:BAABLgAFFH8GAAIHAAMJzho/BQAKAQAHAAMJzho/BQAKAQAAAA==.Swiftmage:BAACLgAFFH8mAAIOAAcJiSB5BwBiAgAOAAcJiSB5BwBiAgAuAAQKfzwAAg4ACQmJJtUAAPYDAA4ACQmJJtUAAPYDAAAA.',
Sy='Sylvian:BAAALgAECgQJBgAAAA==.Syndragonkin:BAAALgAECggJCAAAAA==.Syndrome:BAABLgAECn8iAAMaAAgJmhf3FwDKAQAaAAgJmhf3FwDKAQANAAQJGgbYVQB4AAAAAA==.Syrelea:BAAALgADCgIJAgAAAA==.Sywren:BAAALgAECgEJAwABLgAECgQJCgACAAAAAA==.',
Sz='Szeto:BAABLgAECn8cAAMLAAgJxhfWHwAjAgALAAgJxhfWHwAjAgAPAAEJXg2ILQA1AAAAAA==.',
Ta='Talyndis:BAACLgAFFH8iAAMSAAgJeh25AQBUAgASAAgJah25AQBUAgAKAAMJ0CN2UQCyAAAuAAQKfycAAxIACQnSIyADAHgDABIACQm2IiADAHgDAAoABAn0HSZeAF4BAAAA.Tamyr:BAAALgADCgMJAwABLgAECgQJBQACAAAAAA==.Tashido:BAAALgAECgcJDQAAAA==.Taze:BAAALgAECgcJDQABLgAFFAQJDQAKAFgQAA==.Tazjiingo:BAABLgAECn8UAAMfAAYJmRjzMwCpAQAfAAYJmRjzMwCpAQAJAAUJEg4KRwC9AAAAAA==.',
Te='Teanie:BAAALgADCgYJCgAAAA==.Tenebrium:BAAALgAECgEJBAAAAA==.Terhali:BAAALgAECgcJCAAAAA==.Terrika:BAABLgAECn8gAAIKAAgJzBChSACbAQAKAAgJzBChSACbAQAAAA==.Tetshajeh:BAABLgAECn8mAAIYAAcJqiUBDACGAgAYAAcJqiUBDACGAgAAAA==.Teyliana:BAAALgAECgYJEQAAAA==.',
Th='Theanimal:BAAALgADCgcJCAAAAA==.Therasa:BAAALgAECgQJBQAAAA==.Thewizardguy:BAAALgAECgUJCAAAAA==.Thillarick:BAABLgAECn8sAAIYAAgJtCW9BgDXAgAYAAgJtCW9BgDXAgAAAA==.Thiss:BAAALgAECgQJBwAAAA==.Thiya:BAABLgAECn8XAAIDAAgJeAy7eABcAQADAAgJeAy7eABcAQAAAA==.Thorvard:BAABLgAECn8XAAMeAAYJphpJGABVAQAeAAYJphpJGABVAQAYAAEJVQFttQAcAAAAAA==.Thromanor:BAABLgAECn8UAAIYAAYJKBbEOQA5AQAYAAYJKBbEOQA5AQAAAA==.',
Ti='Tirachill:BAAALgAECgEJAQAAAA==.Tiramisú:BAAALgAECgYJEQAAAA==.Tiranmyashol:BAABLgAECn8gAAIYAAcJ6heWLwDxAQAYAAcJ6heWLwDxAQAAAA==.',
To='Tolken:BAAALgADCgEJAQAAAA==.Too:BAAALgAECgMJAwAAAA==.Toothdk:BAABLgAECn8iAAIIAAgJMSHbHgBtAgAIAAgJMSHbHgBtAgAAAA==.Toppo:BAABLgAECn8uAAIlAAkJ7CHkAQAAAwAlAAkJ7CHkAQAAAwAAAA==.Torfnar:BAAALgAECggJDgAAAA==.Toxicophobia:BAAALgAECgUJCAAAAA==.',
Tr='Tralle:BAAALgAECgQJCAAAAA==.Treebreak:BAABLgAECn8mAAIfAAkJlRA7NgCeAQAfAAkJlRA7NgCeAQAAAA==.Treefity:BAAALgADCgIJAgAAAA==.Trinky:BAAALgAECgUJDQAAAA==.Troublems:BAAALgAECgYJEwAAAA==.',
Ts='Tshi:BAAALgAECgIJAgAAAA==.',
Tu='Turanx:BAAALgAECgIJAgAAAA==.Tutemkhan:BAAALgAECgYJDQAAAA==.',
Tw='Twigrets:BAAALgAECgYJDwAAAA==.',
Ty='Tyrandrea:BAAALgAECgUJDQAAAA==.',
Ud='Udari:BAAALgAECgEJBAAAAA==.',
Ug='Ugîn:BAAALgAECgIJAgAAAA==.',
Um='Umbreona:BAAALgAECgMJAwAAAA==.Umàdbrah:BAABLgAECn8wAAIKAAkJCR8hDgC6AgAKAAkJCR8hDgC6AgAAAA==.',
Un='Unbelievable:BAABLgAECn8nAAIbAAgJXBHiGQB4AQAbAAgJXBHiGQB4AQAAAA==.Unclechuck:BAAALgADCgQJBwAAAA==.Unholylaezel:BAAALgAECgMJCQAAAA==.',
Va='Vaein:BAAALgAECgcJEAAAAA==.Valamor:BAABLgAECn8uAAMgAAkJZhmrGAAaAgAgAAkJZhmrGAAaAgAlAAEJdQWFTQAVAAAAAA==.Valencia:BAAALgADCgIJAgAAAA==.Valicela:BAAALgAECgUJBwAAAA==.Vandamage:BAAALgADCgMJAwAAAA==.Vani:BAAALgAECgQJCwAAAA==.Varenea:BAABLgAECn8ZAAIWAAcJrAfKOAAIAQAWAAcJrAfKOAAIAQAAAA==.Varia:BAAALgADCgYJBgABLgAECgkJJQAIAEsjAA==.Vasharis:BAAALgADCgYJBgAAAA==.',
Ve='Veefib:BAABLgAECn8UAAIcAAgJ1xeLKgDCAQAcAAgJ1xeLKgDCAQAAAA==.Velent:BAAALgADCgEJAQAAAA==.Velhari:BAACLgAFFH8GAAIhAAQJuBhRKwA6AQAhAAQJuBhRKwA6AQAuAAQKfygAAycABgn6I8EGAPYBACEABgnsIUQsAE0CACcABgn6I8EGAPYBAAEuAAUUBAkRAAYAHR8A.Velicerus:BAAALgAECgEJAQAAAA==.Velliri:BAAALgAECgMJAwAAAA==.Velvettwitch:BAABLgAECn8kAAIiAAgJ7Q/1CgBkAQAiAAgJ7Q/1CgBkAQAAAA==.Verahla:BAAALgADCgkJHQAAAA==.Vermis:BAAALgAECgQJBwAAAA==.Verona:BAAALgADCgMJAwAAAA==.Veryaverage:BAABLgAECn8dAAIOAAgJ7xtdSADnAQAOAAgJ7xtdSADnAQAAAA==.Vexation:BAAALgAECgQJCQAAAA==.Vexxd:BAAALgAECgUJDAAAAA==.',
Vi='Vicarious:BAABLgAECn8gAAILAAcJvCKwDgC0AgALAAcJvCKwDgC0AgAAAA==.Vidreaux:BAABLgAECn83AAIBAAkJwRfAAQBLAgABAAkJwRfAAQBLAgAAAA==.Viltry:BAAALgAECgcJBwAAAA==.Vipora:BAACLgAFFH8JAAIFAAMJ6BgkLQDiAAAFAAMJ6BgkLQDiAAAuAAQKfz0AAwUACQkCIjEEABIDAAUACQkCIjEEABIDABcABAnuCkArAMMAAAAA.Visp:BAAALgAECgIJBAAAAA==.',
Vo='Volaura:BAAALgADCgQJBwAAAA==.Volzara:BAABLgAECn8aAAIWAAgJ9xMKGgAPAgAWAAgJ9xMKGgAPAgAAAA==.Voìde:BAAALgAECgMJBAAAAA==.',
Vy='Vynesra:BAAALgADCgEJAgAAAA==.',
We='Wetnurse:BAAALgADCgcJBwAAAA==.',
Wh='Whirz:BAAALgAECgkJEAAAAA==.Whizglizzy:BAAALgADCgQJBAAAAA==.Whosethetank:BAAALgADCgcJEgABLgADCgEJAQACAAAAAA==.',
Wi='Wick:BAAALgAECgEJAgAAAA==.',
Wm='Wmz:BAAALgAECgQJBwAAAA==.',
Wo='Wolfpup:BAAALgAECgcJDwABLgAECggJIgADAOkXAA==.Wolfíe:BAAALgAECgIJAwAAAA==.',
Ww='Wwalle:BAAALgAECgUJBwABLgAECgkJKQAfAP0TAA==.',
Xe='Xenarra:BAAALgADCgUJBQAAAA==.',
Xz='Xzavier:BAAALgAECgQJBAAAAA==.',
['Xä']='Xänsus:BAAALgAECgEJAQAAAA==.',
Ya='Yandros:BAAALgADCgIJAgAAAA==.Yansaa:BAABLgAECn8uAAMfAAgJ7R1sEgCYAgAfAAgJ7R1sEgCYAgAmAAIJUBCdLABxAAAAAA==.Yasutora:BAAALgADCgYJCgABLgAECgkJLgAdAMYgAA==.',
Yf='Yfelshammy:BAABLgAECn89AAILAAkJNhkjEgCQAgALAAkJNhkjEgCQAgAAAA==.',
Yo='Yogiebear:BAAALgADCgUJBQAAAA==.Yogsøthoth:BAAALgADCgYJBgAAAA==.',
Yr='Yrsea:BAAALgADCgIJAgAAAA==.',
Yu='Yubel:BAAALgAECgQJBAABLgAECgcJGAAEABwOAA==.',
Za='Zaevenia:BAAALgADCgkJCwAAAA==.Zakka:BAAALgADCgQJBgAAAA==.Zalraz:BAAALgAECgIJAgAAAA==.Zanebusby:BAABLgAECn8dAAIiAAgJfBZbBwCxAQAiAAgJfBZbBwCxAQAAAA==.Zannahh:BAABLgAECn8eAAIOAAgJsAdfiQBJAQAOAAgJsAdfiQBJAQAAAA==.Zaraa:BAABLgAECn8UAAIPAAYJriEFCgAzAgAPAAYJriEFCgAzAgAAAA==.Zaraë:BAABLgAECn8eAAIhAAgJvh83GQBhAgAhAAgJvh83GQBhAgAAAA==.Zatharis:BAABLgAECn8gAAIKAAcJGRpGNwDWAQAKAAcJGRpGNwDWAQAAAA==.',
Ze='Zepp:BAAALgAECgEJAgAAAA==.Zerax:BAABLgAECn8VAAIOAAcJ9Q8ufQBgAQAOAAcJ9Q8ufQBgAQAAAA==.Zeroshaman:BAAALgAECgQJBAAAAA==.',
Zi='Ziljin:BAAALgADCgkJCQAAAA==.',
Zz='Zzella:BAACLgAFFH8IAAIgAAQJAiHMDwCBAQAgAAQJAiHMDwCBAQAuAAQKfy8AAyAACQluI1IEADUDACAACQluI1IEADUDAAMABAmbE/P1AJgAAAAA.',
['Ða']='Ðabzilla:BAABLgAECn8dAAMgAAgJmBuYHAD4AQAgAAgJmBuYHAD4AQADAAIJhg+iEwFrAAAAAA==.',
['Ðr']='Ðracotalon:BAAALgAECgYJCgAAAA==.Ðragonbeast:BAAALgADCgkJEgAAAA==.',
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
