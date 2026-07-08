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

local lookup = {'Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Druid-Guardian','Priest-Discipline','Paladin-Holy','Warrior-Fury','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','DemonHunter-Havoc','Mage-Frost','DemonHunter-Vengeance','DemonHunter-Devourer','Monk-Mistweaver','Shaman-Restoration','DeathKnight-Blood','DeathKnight-Unholy','Monk-Windwalker','Warrior-Protection','Hunter-BeastMastery','Druid-Restoration','Druid-Feral','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Frost','Rogue-Subtlety','Evoker-Augmentation','Evoker-Preservation','Priest-Holy','Shaman-Enhancement','Druid-Balance','Warrior-Arms','Priest-Shadow','Shaman-Elemental','Rogue-Outlaw','Mage-Arcane','Rogue-Assassination','Monk-Brewmaster','Evoker-Devastation','Mage-Fire',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abberleigh:BAAALgAFFAMJAwAAAA==.',
Ad='Adonya:BAAALgADCgIJAQAAAA==.',
Ae='Aelgagar:BAAALgAECgYJEAAAAA==.Aelirina:BAAALgAECgMJAwAAAA==.',
Ah='Ahamay:BAAALgADCgEJAgAAAA==.',
Ai='Ailde:BAAALgADCgkJDgAAAA==.',
Ak='Akshhan:BAABLgAFFH8IAAIBAAUJlxBKSQAaAQABAAUJlxBKSQAaAQAAAA==.',
Al='Alania:BAAALgADCgYJCAAAAA==.Alaraa:BAABLgAECn8mAAMCAAgJLB4WCQBCAgACAAgJLB4WCQBCAgABAAIJ4xVQMwF7AAABLgAECgIJAgADAAAAAA==.Alarlia:BAABLgAECn8jAAIEAAgJvgtkMQDlAAAEAAgJvgtkMQDlAAAAAA==.Alathor:BAAALgAECgEJAQAAAA==.Algonq:BAABLgAECn8ZAAIFAAYJXAOVCgCpAAAFAAYJXAOVCgCpAAABLgAECgkJNQAGALwFAA==.Alliesofevil:BAABLgAECn8nAAIHAAkJbBU+JgDGAQAHAAkJbBU+JgDGAQAAAA==.Allsar:BAABLgAECn8aAAIEAAkJnB07BgCeAgAEAAkJnB07BgCeAgAAAA==.Alsar:BAAALgAECgQJBwABLgAECgkJGgAEAJwdAA==.Alssar:BAAALgAECgYJCwAAAA==.Alstar:BAAALgAECgEJAgAAAA==.',
Am='Amaraa:BAAALgAECgMJAwAAAA==.Amathus:BAACLgAFFH8OAAQIAAUJkQxLAwDYAAAIAAMJKg5LAwDYAAAJAAQJywRzEACwAAAKAAMJ1gT5iwCtAAAuAAQKf24ABAkACQlmGgcEAEgCAAkACQkaGgcEAEgCAAoACQmWFGtGAMcBAAgABQkNExYEAMcAAAAA.Amaunet:BAAALgADCgUJBQAAAA==.',
An='Anahilis:BAAALgADCgcJCAAAAA==.Andarial:BAABLgAECn8bAAILAAkJDQ/lJwA9AQALAAkJDQ/lJwA9AQAAAA==.Andella:BAAALgAECgIJAgAAAA==.Andreth:BAABLgAECn8WAAIMAAgJ3Qf6HwB4AAAMAAgJ3Qf6HwB4AAAAAA==.Anoxyn:BAAALgAECgcJCQAAAA==.Anthe:BAAALgAECgYJEgAAAA==.Anzul:BAABLgAECn8yAAMBAAkJVCCUJAByAgABAAkJQh+UJAByAgACAAUJxB0TGgBIAQAAAA==.',
Ar='Araestirra:BAABLgAECn8zAAMJAAcJmBI8AgAwAQAJAAYJzBQ8AgAwAQAKAAcJBgc4qwDsAAAAAA==.Arcanmaggy:BAAALgADCgkJHgABLgAFFAYJHQAKAFIEAA==.Ardahh:BAAALgADCgQJBAAAAA==.Arnold:BAABLgAECn8XAAMNAAgJ6hSYCwCjAQANAAgJ6hSYCwCjAQAOAAEJagPLOgEbAAABLgAECgkJGgAEAJwdAA==.Arntdorn:BAAALgADCgEJAQAAAA==.Arroes:BAABLgAECn8ZAAIPAAgJGB/qFgBiAgAPAAgJGB/qFgBiAgAAAA==.',
As='Asahna:BAAALgAECgQJBAAAAA==.',
At='Atlas:BAAALgAECggJCgABLgAECgkJGgAEAJwdAA==.',
Au='Aurrell:BAAALgADCgcJBwAAAA==.',
Av='Avoid:BAAALgAECgMJAwAAAA==.',
Ay='Ayroona:BAABLgAECn8pAAIQAAkJOgpVTgB4AQAQAAkJOgpVTgB4AQAAAA==.',
Az='Azhol:BAAALgAECgQJBAAAAA==.',
Ba='Bacontotem:BAAALgADCgMJBQAAAA==.Baelhal:BAACLgAFFH8ZAAIRAAQJmB08FQBEAQARAAQJmB08FQBEAQAuAAQKfzQAAhEACQmaHUIOACYCABEACQmaHUIOACYCAAAA.Balka:BAAALgADCgYJCAAAAA==.Barbaydos:BAAALgADCggJCQAAAA==.Barenjager:BAAALgAECgEJAQAAAA==.Basement:BAABLgAECn8gAAIOAAcJph6pBgBAAQAOAAcJph6pBgBAAQAAAA==.',
Be='Beastnite:BAAALgADCgkJKQABLgAECgkJGwASANANAA==.Bellaburger:BAABLgAFFH8IAAITAAQJsgYfIgDOAAATAAQJsgYfIgDOAAAAAA==.Bellissidan:BAAALgAECgEJAwAAAA==.Benedin:BAAALgAECgYJEQABLgAECgkJRgAIALYgAA==.',
Bi='Bigpapapete:BAAALgAECgYJAwAAAA==.Bigtex:BAABLgAECn81AAMHAAkJewujBgAOAQAHAAkJRwujBgAOAQAUAAMJgwzKPAB/AAAAAA==.Biped:BAABLgAECn8zAAIIAAkJPhNbCADkAQAIAAkJPhNbCADkAQAAAA==.Birill:BAAALgAECgEJAgAAAA==.Bishul:BAAALgAECggJCQAAAA==.',
Bl='Blackdeath:BAACLgAFFH8FAAISAAIJSgmG6wB+AAASAAIJSgmG6wB+AAAuAAQKfy8AAhIACQn1HEkHAGIBABIACQn1HEkHAGIBAAAA.',
Bo='Bombarian:BAAALgAECgUJCwAAAA==.Bone:BAAALgAECgEJAQAAAA==.Boomstique:BAABLgAECn87AAIVAAkJ3R1AAwA3AgAVAAkJ3R1AAwA3AgAAAA==.Boondocka:BAABLgAECn82AAIVAAkJ9BqFHAB6AgAVAAkJ9BqFHAB6AgAAAA==.',
Br='Brewco:BAACLgAFFH8SAAIWAAUJ1hLaLQD9AAAWAAUJ1hLaLQD9AAAuAAQKfzkABBYACQkEHKYUAJACABYACQkEHKYUAJACABcABgnDG1YSAJYBAAQABQl6Dw49ALIAAAAA.Brewer:BAAALgAECgEJAQAAAA==.Brickmebtch:BAAALgAECgYJBwAAAA==.Bruda:BAAALgAECgIJAwAAAA==.Brutalís:BAABLgAECn8oAAIVAAkJFhICPwDmAQAVAAkJFhICPwDmAQAAAA==.',
Bt='Btrain:BAABLgAECn8hAAMCAAYJ3AqaMQCfAAABAAYJzQZa9ADFAAACAAUJgAyaMQCfAAAAAA==.',
['Bó']='Bóunty:BAABLgAECn8bAAQYAAcJwx8lHwCjAQAYAAcJrh0lHwCjAQAVAAQJNx5HXgBNAQAZAAEJPgJtmAAeAAAAAA==.',
Ca='Camaryn:BAAALgADCgIJAgAAAA==.Canadia:BAAALgAECgQJBgAAAA==.Caritta:BAAALgAECgQJBAAAAA==.Catdaddan:BAAALgADCgYJBgAAAA==.Cattnip:BAAALgAECgEJAQAAAA==.Cavisch:BAABLgAECn9GAAMIAAkJtiAcAQD/AgAIAAkJtiAcAQD/AgAKAAkJWBi7OwDsAQAAAA==.',
Ce='Cedric:BAAALgAECgIJAgABLgAECgcJCAADAAAAAA==.Cenobité:BAABLgAECn8yAAIaAAkJ5Bn9AADiAQAaAAkJ5Bn9AADiAQAAAA==.Cerr:BAAALgAECgMJBAAAAA==.',
Ch='Chamber:BAAALgAECgYJCAABLgAECgcJIAAOAKYeAA==.Chantilly:BAAALgADCgYJDwAAAA==.Chaosmaster:BAAALgAECgMJAwAAAA==.Chardee:BAABLgAFFH8HAAIbAAMJlBUmDQAVAQAbAAMJlBUmDQAVAQAAAA==.Charmeleon:BAABLgAECn8UAAMcAAgJCRJ1QQAjAQAcAAgJCRJ1QQAjAQAdAAIJfAwbNABWAAAAAA==.Charmin:BAAALgADCgUJBQAAAA==.Chicka:BAAALgAECgIJAgABLgAECgYJCQADAAAAAA==.Chiff:BAAALgADCgUJAwAAAA==.Chilledog:BAAALgADCgQJBAAAAA==.Chip:BAAALgAECgMJBgAAAA==.',
Ci='Cirax:BAABLgAECn8qAAIVAAgJdBcvPgDpAQAVAAgJdBcvPgDpAQAAAA==.Cirin:BAAALgADCgEJAQAAAA==.Citruscoolin:BAAALgAECgEJAQAAAA==.',
Cl='Cleetess:BAAALgAECgEJAQAAAA==.Clenton:BAABLgAECn9wAAMCAAkJNw33AgAvAQACAAkJ1gv3AgAvAQABAAgJCQhFrwAgAQAAAA==.Clipper:BAAALgADCgYJBgAAAA==.',
Co='Cobrakai:BAAALgAECgIJAgAAAA==.Comeatmebro:BAAALgAECgEJAQABLgAFFAQJGAAeAL8eAA==.Cowboyup:BAAALgADCgYJBgAAAA==.',
Cr='Crichton:BAACLgAFFH8UAAIOAAQJ9Rl5PgAtAQAOAAQJ9Rl5PgAtAQAuAAQKfzIAAg4ACQm0IYIMAOECAA4ACQm0IYIMAOECAAAA.Cronnan:BAAALgAECgUJBQAAAA==.Crowford:BAABLgAECn82AAIVAAkJPRMGDAA2AQAVAAkJPRMGDAA2AQAAAA==.',
Cy='Cyris:BAAALgAECgYJCwABLgAECgkJPwAfAO8HAA==.',
['Cá']='Cástle:BAAALgAECgEJAQABLgAECgcJIAAOAKYeAA==.',
Da='Daemonfaust:BAAALgAECgYJDwAAAA==.Daevahna:BAAALgADCgYJBgAAAA==.Dahtty:BAAALgAECgYJBwAAAA==.Dakdeekay:BAACLgAFFH8FAAISAAMJDBFuMQDZAAASAAMJDBFuMQDZAAAuAAQKfyUAAhIACQlbF7UwADwCABIACQlbF7UwADwCAAAA.Daksclaw:BAAALgAFFAIJAgABLgAFFAMJBQASAAwRAA==.Daksmash:BAAALgAECgUJCAABLgAFFAMJBQASAAwRAA==.Dakstab:BAAALgADCgkJCQAAAA==.Dalsar:BAABLgAECn8UAAMEAAgJywfxNwDHAAAEAAgJywfxNwDHAAAWAAQJKAlVCwCFAAAAAA==.Darkbrew:BAAALgADCgYJCAABLgAECgkJNwACAJwiAA==.Darkfes:BAAALgAECgEJAQAAAA==.Darkmiza:BAACLgAFFH8dAAIKAAYJUgRnbgDlAAAKAAYJUgRnbgDlAAAuAAQKfzsAAwoACAl1EVJlAHMBAAoACAl1EVJlAHMBAAkAAglDC0lYAGYAAAAA.Darkseer:BAAALgAFFAIJBAAAAA==.Darthbluto:BAAALgAECgUJDQABLgAECgYJDwADAAAAAA==.Dasham:BAAALgAECgQJBAAAAA==.Daymann:BAABLgAECn8iAAIBAAkJHRa8SQDpAQABAAkJHRa8SQDpAQAAAA==.',
De='Deadazz:BAAALgADCgYJCgAAAA==.Deadmangalad:BAABLgAECn8vAAMaAAkJvArfFQAqAQAaAAkJvArfFQAqAQARAAEJFATyaQAWAAAAAA==.Deathnotes:BAAALgADCgEJAQAAAA==.Deathquina:BAAALgAECgMJAwAAAA==.Deathtickle:BAAALgAECgcJAwAAAA==.Deedees:BAABLgAECn8eAAIgAAgJ5QZ8QwD/AAAgAAgJ5QZ8QwD/AAAAAA==.Demonbo:BAABLgAECn8aAAIOAAgJiBQUZABfAQAOAAgJiBQUZABfAQAAAA==.Demondrink:BAAALgAECgQJBgAAAA==.Demonhandler:BAAALgADCggJDwAAAA==.Deo:BAACLgAFFH8YAAMHAAQJGiDkEQB4AQAHAAQJGiDkEQB4AQAhAAMJMBTPKADKAAAuAAQKfz8AAwcACQkmJAAEACYDAAcACQkmJAAEACYDACEAAgmSDeVjAFoAAAAA.Depression:BAAALgADCgUJBQAAAA==.Derpixion:BAABLgAECn8tAAMVAAgJYhlFJwAcAgAVAAgJYhlFJwAcAgAYAAUJYQtJPgDSAAAAAA==.Dessirius:BAAALgAECgEJAQAAAA==.Dethphalanax:BAAALgADCgUJCQAAAA==.',
Di='Digbie:BAAALgADCgYJBwAAAA==.Digs:BAAALgADCgMJAwAAAA==.Dirtnåp:BAAALgAECgYJEwAAAA==.Diskbänk:BAAALgAECgUJBwAAAA==.',
Dk='Dkho:BAACLgAFFH8FAAIMAAMJ7gNqkwCuAAAMAAMJ7gNqkwCuAAAuAAQKfxUAAgwACAnCDbV/AHgBAAwACAnCDbV/AHgBAAAA.',
Dr='Drago:BAAALgAECgEJBAAAAA==.Dragontoast:BAAALgAECggJEgAAAA==.Dral:BAEALgADCgkJKAAAAA==.Draygun:BAAALgAECgcJBwABLgAFFAQJGAAHABogAA==.Drphilyobody:BAABLgAECn8cAAISAAcJCQhMsgARAQASAAcJCQhMsgARAQAAAA==.Drui:BAABLgAECn8dAAIgAAgJsQ4dNgBkAQAgAAgJsQ4dNgBkAQAAAA==.Druidïan:BAAALgAECgQJBQAAAA==.',
Du='Duelittle:BAABLgAECn8qAAIiAAcJmQ1zBwDfAAAiAAcJmQ1zBwDfAAAAAA==.',
Dy='Dynwor:BAAALgAECgEJAgAAAA==.',
['Dé']='Dérailed:BAAALgAECgUJEgAAAA==.',
['Dî']='Dîz:BAAALgADCgEJAQAAAA==.',
Ea='Easme:BAABLgAECn8oAAMYAAkJJgv3AwDtAAAYAAkJJgv3AwDtAAAZAAUJRANPYgC3AAAAAA==.Eatmyfrontal:BAABLgAECn87AAIMAAkJQBoAPwAgAgAMAAkJQBoAPwAgAgAAAA==.',
Eb='Ebbola:BAAALgADCgcJDgAAAA==.Ebon:BAAALgAECgMJAwABLgAECggJDAADAAAAAA==.',
Eh='Ehsinat:BAAALgADCgYJBgAAAA==.',
El='Elaraa:BAAALgAECgYJBwAAAA==.Elaric:BAAALgAECgcJCAAAAA==.Elger:BAAALgADCgEJAgAAAA==.Elvi:BAAALgAECgEJAQAAAA==.',
Em='Emory:BAAALgADCgEJAQAAAA==.',
En='Engi:BAAALgAECgcJDAAAAA==.',
Ep='Epikrate:BAABLgAECn8fAAMKAAgJURl8QADbAQAKAAcJIRl8QADbAQAJAAMJ4hiqSACUAAAAAA==.',
Es='Escaper:BAABLgAECn84AAIaAAkJcxLOCwC7AQAaAAkJcxLOCwC7AQAAAA==.',
Ex='Extrema:BAAALgAECggJEgAAAA==.',
Ez='Ezsdruid:BAAALgAECgkJCQAAAA==.',
Fa='Faesha:BAAALgAECgEJAQAAAA==.Fallenash:BAAALgADCgMJAwABLgAFFAQJFgAMAGsfAA==.Fallenembers:BAACLgAFFH8WAAIMAAQJax/0QwBhAQAMAAQJah/0QwBhAQAuAAQKfzsAAgwACQlJJb8GAEsDAAwACQlJJb8GAEsDAAAA.Famine:BAABLgAECn8dAAMSAAgJ0AWlvAACAQASAAgJwwSlvAACAQAaAAUJzAf7DADfAAAAAA==.Farquaadtwo:BAAALgAECgIJAgAAAA==.',
Fe='Fearofthdark:BAAALgADCgEJAQAAAA==.',
Ff='Fflar:BAAALgADCgUJBQABLgAECgkJAgADAAAAAA==.',
Fh='Fhait:BAABLgAECn8XAAMFAAYJEwxLCQDFAAAFAAUJYg1LCQDFAAAiAAYJZwWzCgClAAABLgAECgkJNwATAFoNAA==.',
Fi='Firsttimepvp:BAACLgAFFH8HAAIbAAIJJg3xNQCJAAAbAAIJJg3xNQCJAAAuAAQKfx4AAhsACQnaE6kUAPwBABsACQnaE6kUAPwBAAAA.',
Fl='Flow:BAAALgADCgYJBgAAAA==.',
Fr='Frenchtoast:BAAALgAECgIJAgAAAA==.Frostyflaker:BAAALgAECgUJDAAAAA==.',
Ga='Gaiã:BAAALgADCgEJAgAAAA==.Galadan:BAABLgAECn8ZAAMEAAYJIA3oBwCwAAAEAAYJIA3oBwCwAAAXAAQJSgSDQABbAAABLgAECgkJLwAaALwKAA==.Garrekton:BAAALgADCgIJAgABLgAECgkJRgAIALYgAA==.Gaskelmarg:BAAALgAECgUJDwAAAA==.',
Ge='Gellane:BAAALgAECgMJAwAAAA==.',
Gh='Ghosty:BAABLgAECn8hAAQFAAkJIRWWHwDRAQAFAAkJsRGWHwDRAQAeAAcJpAuKTgD+AAAiAAEJcAEanAAXAAAAAA==.Ghuun:BAAALgADCgEJAgABLgAFFAMJCAAPAAoMAA==.',
Gi='Gigaweed:BAABLgAFFH8IAAIPAAMJCgx/RQCOAAAPAAMJCgx/RQCOAAAAAA==.',
Go='Goblinlayer:BAAALgAECgYJEwAAAA==.Goldtusk:BAABLgAECn8iAAIXAAkJHBVbDgDQAQAXAAkJHBVbDgDQAQAAAA==.Gooey:BAAALgADCggJDgAAAA==.Gostann:BAABLgAECn8mAAIKAAkJlRclJwBAAgAKAAkJlRclJwBAAgAAAA==.',
Gr='Grayparser:BAAALgADCgYJCQAAAA==.Grimsly:BAAALgAECgEJAQAAAA==.Grundler:BAAALgAFFAEJAQAAAA==.Gryphone:BAAALgADCgkJEAAAAA==.',
Gu='Gurinendo:BAAALgAECgEJAgAAAA==.Gustwin:BAAALgAECgQJBgAAAA==.',
['Gà']='Gàins:BAAALgAECgMJAwABLgAECgkJNwACAJwiAA==.',
Ha='Hakmud:BAAALgADCgYJCwAAAA==.Halsin:BAAALgADCgMJAwABLgAECggJIQAjAD0aAA==.Hamshammy:BAAALgAECgEJAQAAAA==.',
He='Heftydin:BAAALgAECgMJCQAAAA==.Heftymists:BAAALgAECgUJBQAAAA==.Heftystomp:BAAALgADCgUJBQAAAA==.Heftyvoid:BAAALgADCgEJAQAAAA==.Hela:BAAALgADCgcJBwAAAA==.Hercyderc:BAAALgAECgEJAQABLgAFFAIJBQAOADYgAA==.Hettokal:BAAALgAECgcJCQAAAA==.Heyitsjimbo:BAAALgADCgUJCQAAAA==.',
Ho='Holierhtanu:BAAALgADCgQJBwAAAA==.Holyhellion:BAABLgAECn8dAAIOAAkJchEFRQC4AQAOAAkJchEFRQC4AQAAAA==.Hondojoe:BAACLgAFFH8YAAIeAAQJvx5lDwBbAQAeAAQJvx5lDwBbAQAuAAQKfzsAAx4ACQnuIEoLAJsCAB4ACQnuIEoLAJsCAAUAAgnYBv1uAE0AAAAA.Honeydrake:BAAALgAECgYJCAAAAA==.Hopewell:BAABLgAECn81AAIGAAkJvAUSRgAnAQAGAAkJvAUSRgAnAQAAAA==.',
Hu='Huginn:BAAALgADCgEJAQAAAA==.Hugnsnuggle:BAABLgAECn83AAINAAkJMgyKAQBKAQANAAkJMgyKAQBKAQABLgAECgkJNwATAFoNAA==.Huhu:BAABLgAECn8ZAAIHAAkJrxRhKwCnAQAHAAkJrxRhKwCnAQAAAA==.Huma:BAAALgAECgYJEAABLgAFFAQJCgAVAAAOAA==.Hundreg:BAAALgADCgYJBQAAAA==.',
Ib='Ibn:BAABLgAECn8sAAIhAAkJBws1HwBkAQAhAAkJBws1HwBkAQAAAA==.',
Ic='Icyhot:BAAALgAECgMJBQAAAA==.',
Id='Ideal:BAAALgADCgYJDAAAAA==.',
Il='Illaris:BAAALgADCgIJAgAAAA==.',
In='Infiniity:BAAALgAECgMJCQAAAA==.Inksmear:BAAALgAECgEJAQAAAA==.',
Ir='Irielle:BAAALgAECgUJEAAAAA==.',
Is='Ishanllin:BAAALgAECgIJAgAAAA==.',
Iv='Ivarurngamet:BAABLgAECn8iAAIOAAkJyRfaLgALAgAOAAkJyRfaLgALAgAAAA==.Ivylyn:BAAALgAECgkJDgAAAA==.',
Ix='Ixiyá:BAABLgAECn89AAMQAAkJNCNtBABxAwAQAAkJNCNtBABxAwAjAAEJzghXrgAqAAAAAA==.Ixií:BAAALgAECgEJAwAAAA==.Ixì:BAABLgAECn8XAAIWAAcJ1x31IQA4AgAWAAcJ1x31IQA4AgAAAA==.',
Ja='Jakbequick:BAAALgAECgEJAQAAAA==.Jakeyprogue:BAAALgAFFAIJAwABLgAFFAIJBgASAL4cAA==.Jakota:BAAALgADCgkJFAAAAA==.Jakskeleton:BAABLgAECn8fAAIRAAgJ2xoYEAAKAgARAAgJ2xoYEAAKAgAAAA==.Jarobus:BAAALgAECgYJDgAAAA==.Jay:BAAALgADCgEJAQAAAA==.Jaynamir:BAAALgAECgYJEwAAAA==.Jayp:BAAALgAECgMJAwAAAA==.',
Jb='Jbernn:BAAALgAECgEJAQAAAA==.',
Je='Jeamica:BAAALgADCgcJCgAAAA==.',
Jo='Joemacho:BAAALgAECgcJEwABLgAFFAQJGAAeAL8eAA==.Joshtee:BAAALgAECgMJBQAAAA==.Joslyn:BAAALgAECgQJBQAAAA==.Jourdan:BAAALgADCgcJDQAAAA==.',
Ju='Judax:BAACLgAFFH8IAAIjAAMJaQ8FNwCyAAAjAAMJaQ8FNwCyAAAuAAQKfz0AAiMACQm0GyUTAFUCACMACQm0GyUTAFUCAAAA.Justagirl:BAABLgAECn83AAITAAkJWg3rMwA0AQATAAkJWg3rMwA0AQAAAA==.Justiceboyd:BAAALgADCgMJAwAAAA==.Juti:BAAALgAECgYJDAAAAA==.',
Jy='Jymion:BAAALgADCgEJAQAAAA==.',
['Jú']='Júun:BAAALgADCgEJAQAAAA==.',
Ka='Kadooka:BAACLgAFFH8FAAIVAAIJIQnPNgCNAAAVAAIJIQnPNgCNAAAuAAQKfyYAAhUACAmkGWYIAHcBABUACAmkGWYIAHcBAAAA.Kahlyn:BAAALgAECgYJCwAAAA==.Kajax:BAABLgAECn8qAAIbAAgJISMwCAANAwAbAAgJISMwCAANAwAAAA==.Kaldaran:BAABLgAECn8YAAQaAAkJjBviAgAIAQARAAkJ1BnKGwB+AQAaAAMJ3x3iAgAIAQASAAIJtQTrUwFOAAAAAA==.Kallan:BAAALgAECgYJCgABLgAECgkJNwACAJwiAA==.Kalleigh:BAAALgADCgQJBAABLgAECgkJPwAfAO8HAA==.Karen:BAAALgADCgcJHAAAAA==.Karinn:BAAALgADCgEJAQAAAA==.Karne:BAAALgADCgYJBgAAAA==.Katira:BAAALgAECgEJAQAAAA==.Kazarath:BAAALgADCgUJBQAAAA==.',
Ke='Keeganw:BAABLgAECn8fAAMRAAYJThuSJgAfAQARAAYJThuSJgAfAQASAAEJKRLZMQA5AAAAAA==.Keelay:BAABLgAECn9LAAIGAAkJ/R8GAQBmAgAGAAkJ/R8GAQBmAgAAAA==.',
Kh='Kheegorn:BAABLgAECn8bAAIBAAgJjRhqTwDzAQABAAgJjRhqTwDzAQABLgAFFAMJBQASAAwRAA==.Khyla:BAAALgAECgEJAQAAAA==.',
Ki='Killua:BAAALgADCgYJBgABLgADCgcJCwADAAAAAA==.Kimiko:BAAALgAECgcJEAAAAA==.',
Kl='Klaw:BAAALgAECgQJBAABLgAECggJKgAbACEjAA==.',
Ko='Koffcmorbius:BAAALgAECgQJBwAAAA==.Koriban:BAABLgAECn8lAAIMAAkJaA69aQCoAQAMAAkJaA69aQCoAQAAAA==.Korreban:BAAALgAECgYJBgABLgAECgkJJQAMAGgOAA==.',
Kr='Kra:BAAALgAECgEJAgABLgAFFAMJCAAPAAoMAA==.Kraken:BAACLgAFFH8GAAIJAAMJ1hKrDQDIAAAJAAMJ1hKrDQDIAAAuAAQKfysAAgkACQlzIvIAAAUDAAkACQlzIvIAAAUDAAEuAAUUAwkIAA8ACgwA.Krim:BAAALgADCgYJBgAAAA==.',
Ku='Kubb:BAABLgAECn8/AAIfAAkJ7wfgAgAlAQAfAAkJ7wfgAgAlAQAAAA==.Kunst:BAAALgADCgEJAQAAAA==.',
Kw='Kweh:BAACLgAFFH8ZAAIXAAYJlh+sAQDcAQAXAAYJlh+sAQDcAQAuAAQKfy0AAxcACQk6IxoFAMACABcACQk6IxoFAMACACAABQkbDqZGAPEAAAAA.',
Ky='Kytrina:BAAALgAECgEJAQAAAA==.',
['Kê']='Kêlsen:BAAALgAECgUJBwAAAA==.',
La='Lachupacabra:BAAALgAECgEJAQAAAA==.Larrissa:BAABLgAECn8rAAMIAAkJZQfZEwAyAQAIAAkJZQfZEwAyAQAJAAEJggPhewAlAAAAAA==.Larry:BAABLgAFFH8TAAIOAAYJghRiPgAtAQAOAAYJghRiPgAtAQAAAA==.Laurlynn:BAAALgAECggJEQAAAA==.Lavina:BAAALgADCgUJBQAAAA==.',
Le='Lenwe:BAAALgAECgYJCgABLgAECgcJLQAeAGwOAA==.Lettuceprey:BAABLgAECn87AAIeAAkJhg/TBAAvAQAeAAkJhg/TBAAvAQAAAA==.',
Li='Lierise:BAABLgAECn8RAAQSAAcJzRnFBwBVAQASAAcJzRnFBwBVAQARAAMJ5BCVPACfAAAaAAEJJxO4CgA7AAAAAA==.Lies:BAAALgADCgkJCQAAAA==.Lightsnipe:BAAALgAECgQJBAAAAA==.Lilkelp:BAAALgAECgYJBwAAAA==.Lilspazz:BAAALgADCgMJAwAAAA==.Lithiri:BAAALgAECgUJBgABLgAECggJIwASAHAgAA==.',
Lo='Lockatute:BAAALgAECgkJEgAAAA==.Lockdeath:BAAALgAECgQJCQAAAA==.Loric:BAAALgADCgkJCQAAAA==.Loxia:BAABLgAECn8XAAIJAAkJxA1yEwAWAQAJAAkJxA1yEwAWAQAAAA==.',
Lu='Lucille:BAACLgAFFH8FAAIMAAEJfAZfVABEAAAMAAEJfAZfVABEAAAuAAQKfx8AAgwACAnjERwOABMBAAwACAnjERwOABMBAAAA.Luckett:BAAALgADCgEJAQAAAA==.Lucrotia:BAAALgADCgQJBAAAAA==.Luukmosh:BAAALgAECgUJCQAAAA==.',
Ma='Maavarra:BAABLgAECn8zAAMXAAkJOCIpAAAaAwAXAAkJOCIpAAAaAwAWAAQJLRSaBwDXAAAAAA==.Madilyons:BAAALgADCgIJAgAAAA==.Madischa:BAAALgAECgcJEQAAAA==.Magicdance:BAACLgAFFH8JAAIjAAQJxQJnOACtAAAjAAQJxQJnOACtAAAuAAQKfzsAAxAACQmHEUZLAIMBABAACQmHEUZLAIMBACMACQmeCtIIAMYAAAAA.Magolthel:BAAALgADCgYJCQAAAA==.Maimgame:BAABLgAECn8WAAIXAAgJchK/CwACAgAXAAgJchK/CwACAgAAAA==.Majicbob:BAABLgAECn8hAAIjAAgJPRoSHgDxAQAjAAgJPRoSHgDxAQAAAA==.Maki:BAABLgAECn8UAAMkAAkJ/BTeEgDcAAAbAAkJ/BRXLwCJAQAkAAUJxRDeEgDcAAAAAA==.Mansion:BAAALgADCgQJBgABLgAECgcJIAAOAKYeAA==.Marilune:BAAALgADCggJCQAAAA==.Marn:BAAALgADCgQJBAAAAA==.Marthran:BAAALgADCgIJAgAAAA==.Maxlin:BAAALgAECgIJAwAAAA==.',
Mc='Mctowlie:BAAALgAECgYJCAAAAA==.',
Me='Mehänemäntä:BAAALgAECggJEgAAAA==.Meldo:BAAALgADCggJDQAAAA==.Mellinessa:BAABLgAECn8aAAMaAAcJqBXJEwBAAQASAAYJJRKQlABXAQAaAAUJWBXJEwBAAQAAAA==.Mena:BAAALgADCgUJBgAAAA==.Merixa:BAAALgADCgEJAQAAAA==.',
Mf='Mfdkidney:BAAALgAECgIJAgAAAA==.',
Mi='Midou:BAAALgAECgMJAwABLgAFFAQJCQAjAMUCAA==.Minthraxis:BAAALgADCgEJAQAAAA==.Misaun:BAAALgAECgEJAgABLgAECgMJBAADAAAAAA==.Misericorde:BAACLgAFFH8QAAITAAQJUyTRCACNAQATAAQJUyTRCACNAQAuAAQKfzwAAhMACQkYJqUBAF0DABMACQkYJqUBAF0DAAAA.Misstreater:BAABLgAECn8mAAMMAAgJZArbDgAKAQAMAAgJ6QnbDgAKAQAlAAcJyQYkCgDpAAAAAA==.',
Mo='Momentomori:BAABLgAECn8gAAIKAAkJvghkbwBcAQAKAAkJvghkbwBcAQAAAA==.Monbow:BAAALgAECgMJBwABLgAECggJGgAOAIgUAA==.Monocerotis:BAAALgAECgQJBAAAAA==.Morishima:BAACLgAFFH8XAAIbAAQJ6xmoFgBYAQAbAAQJ6xmoFgBYAQAuAAQKf08AAxsACQlkJPcCACIDABsACQlkJPcCACIDACYAAQkJFtklAD0AAAAA.Morthis:BAABLgAECn84AAMZAAkJPhOyAADoAQAZAAkJPhOyAADoAQAYAAMJWgM5WABMAAAAAA==.',
Mt='Mtpoccy:BAAALgADCgYJBgAAAA==.',
Mu='Multipàss:BAAALgADCgcJCgAAAA==.',
My='Mydarling:BAAALgAFFAIJAwAAAA==.Mymoon:BAAALgAECgIJAgAAAA==.Myris:BAACLgAFFH8HAAISAAMJ7Q+IRgCZAAASAAMJ7Q+IRgCZAAAuAAQKfzEAAhIACQmQHHAnAGUCABIACQmQHHAnAGUCAAAA.',
Na='Narcan:BAAALgAECgUJDQAAAA==.Naturalchi:BAABLgAECn8wAAMTAAkJByWbAgBCAwATAAkJiiSbAgBCAwAnAAgJ8x5yDABuAgAAAA==.',
Nb='Nbi:BAAALgAECgEJAQAAAA==.',
Ne='Nefilion:BAABLgAFFH8GAAISAAIJ7wsI6QB/AAASAAIJ7wsI6QB/AAAAAA==.Nemas:BAABLgAECn8hAAICAAgJrxnuDgDVAQACAAgJrxnuDgDVAQAAAA==.Neverleft:BAAALgAECgUJCAAAAA==.Nezin:BAABLgAECn8tAAQcAAkJyhhqAQDcAQAcAAkJiRdqAQDcAQAoAAYJJRNDDwAXAQAdAAIJuQ2jQABlAAAAAA==.',
Ni='Nightrun:BAAALgADCgcJCwAAAA==.Nightrunnêr:BAAALgAECgUJCwABLgAECgkJNwACAJwiAA==.Nineadin:BAACLgAFFH8UAAMBAAQJnwsQWAAAAQABAAQJnwsQWAAAAQAGAAQJLhe7CgD4AAAuAAQKfycAAwYACQmYHU0TAHgCAAYACQmYHU0TAHgCAAEAAgkjHZ0IAa4AAAAA.Nineshots:BAAALgAFFAMJBAABLgAFFAQJFAABAJ8LAA==.Ninetoads:BAAALgAECgcJDQABLgAFFAQJFAABAJ8LAA==.Nirvanas:BAABLgAECn8dAAIXAAgJ/A10HQAeAQAXAAgJ/A10HQAeAQAAAA==.Niyoko:BAAALgADCgcJBwAAAA==.',
No='Nomik:BAABLgAECn8tAAMeAAcJbA6KNwAgAQAeAAcJbA6KNwAgAQAiAAYJ1Qe6YwCMAAAAAA==.Nonah:BAAALgADCgEJAgAAAA==.North:BAAALgAECggJCAAAAA==.',
Nu='Nuke:BAABLgAECn8VAAIVAAQJvBmBEQDyAAAVAAQJvBmBEQDyAAAAAA==.Nullspace:BAABLgAECn8qAAMeAAkJXhq+FAAvAgAeAAkJXhq+FAAvAgAiAAMJAQzfCwCRAAAAAA==.Nunskee:BAAALgAECgQJBAAAAA==.',
['Ní']='Níght:BAABLgAECn85AAIEAAgJKRdYFQCqAQAEAAgJKRdYFQCqAQAAAA==.',
Oa='Oaken:BAAALgADCgkJCgAAAA==.',
Oc='Occultivated:BAAALgAECgQJBgAAAA==.',
Od='Oddtotem:BAAALgADCgMJAwAAAA==.',
Oh='Ohhk:BAAALgAECgMJAwAAAA==.',
Om='Ommû:BAAALgAECgMJCAAAAA==.',
Op='Op:BAAALgAECgIJAgABLgAFFAMJCAAPAAoMAA==.',
Or='Orillar:BAAALgADCgEJAQAAAA==.',
Pa='Pakeydk:BAABLgAFFH8GAAISAAIJvhxWxgCfAAASAAIJvhxWxgCfAAAAAA==.Palacia:BAAALgAECggJEQAAAA==.Pancakedealr:BAAALgAECgUJEAAAAA==.Pancakeeater:BAAALgAECgUJCgAAAA==.Pappabeary:BAAALgADCgEJAQAAAA==.',
Pe='Peaches:BAAALgAECgEJAQAAAA==.Peerow:BAAALgADCgMJAwAAAA==.Permelia:BAAALgADCgkJDwAAAA==.Petrichorica:BAABLgAECn8bAAIjAAkJFAPfCwCUAAAjAAkJFAPfCwCUAAAAAA==.Peí:BAAALgAECgEJAQAAAA==.',
Ph='Phatjake:BAAALgADCgYJBgAAAA==.',
Pi='Ping:BAABLgAFFH8GAAIPAAYJ3RQpBwDTAQAPAAYJ3RQpBwDTAQAAAA==.Pintobeans:BAABLgAECn8XAAIVAAkJlQVJdwBRAQAVAAkJlQVJdwBRAQAAAA==.',
Pl='Plutonix:BAAALgAECgMJBQAAAA==.',
Pr='Preachêr:BAAALgAECgQJCQABLgAECgkJNwACAJwiAA==.Prohteus:BAAALgAECgEJAQABLgAECgMJBQADAAAAAA==.',
Pu='Puuhceew:BAABLgAECn8gAAIeAAgJUw61NgAlAQAeAAgJUw61NgAlAQAAAA==.',
Qu='Quan:BAEALgADCgcJCQABLgADCgkJKAADAAAAAA==.Quelaag:BAAALgADCgQJBAAAAA==.Quenthel:BAAALgAECgkJAgAAAA==.Quiescent:BAABLgAECn8pAAIOAAgJdRr2KQAiAgAOAAgJdRr2KQAiAgAAAA==.Quina:BAAALgAECgQJBwAAAA==.',
Ra='Ragingtides:BAAALgADCgEJAQAAAA==.Rainera:BAABLgAECn8xAAMIAAkJJSW8AQDWAgAIAAkJJSW8AQDWAgAKAAEJAxH1OgE1AAABLgAFFAcJHAANAPcjAA==.Ramanas:BAABLgAECn8bAAMiAAkJ0BPOLwBgAQAiAAgJVxTOLwBgAQAFAAYJnBGILQAxAQAAAA==.Ramrod:BAAALgAECgIJAwAAAA==.Randomizwe:BAABLgAECn8uAAIBAAkJtB5EIwB4AgABAAkJtB5EIwB4AgAAAA==.Raspet:BAAALgADCgIJAgAAAA==.Rattles:BAAALgADCgcJCwAAAA==.Raynu:BAAALgAECgEJAwAAAA==.Raín:BAAALgAECggJDwAAAA==.',
Re='Reisa:BAAALgAECgEJAQAAAA==.Relearning:BAABLgAECn8zAAIKAAkJYBDQBwAqAQAKAAkJYBDQBwAqAQAAAA==.Relyn:BAABLgAECn8UAAIOAAgJWQchigAMAQAOAAgJWQchigAMAQAAAA==.Resurgencê:BAABLgAECn83AAICAAkJnCJhAAC2AgACAAkJnCJhAAC2AgAAAA==.Retalltheway:BAAALgADCgEJAQAAAA==.',
Ri='Riggler:BAAALgAECgcJBwAAAA==.Riordan:BAABLgAECn8mAAMBAAgJ6BQykgBOAQABAAcJChQykgBOAQACAAQJ9xPgJQDnAAAAAA==.',
Ro='Rohz:BAAALgADCgIJAgABLgAECgcJIAAOAKYeAA==.Rojeton:BAAALgADCgUJBwAAAA==.Rosenth:BAAALgADCggJEwAAAA==.Rotandroll:BAAALgAECgcJDwAAAA==.Rothema:BAABLgAECn8lAAMjAAkJ4wuLCADLAAAjAAkJ4wuLCADLAAAQAAcJ+APskwCvAAAAAA==.Routh:BAAALgAECgEJAQAAAA==.',
Rw='Rwlmaster:BAABLgAECn9AAAIRAAkJIxuuDwAQAgARAAkJIxuuDwAQAgAAAA==.',
Ry='Rynzia:BAACLgAFFH8ZAAMoAAQJMhkiBAAtAQAcAAQJMhmcJwAuAQAoAAQJMxMiBAAtAQAuAAQKf0cABCgACQngIa0BANECACgACQktH60BANECABwACQnJIGEMAJUCAB0ABwnnErsSAJ0BAAAA.',
Sa='Sadabacus:BAAALgAECgEJAgAAAA==.Sagetempest:BAAALgADCgEJAQAAAA==.Sagittarian:BAAALgADCgUJBwAAAA==.Sandwiches:BAABLgAECn8WAAIWAAgJrRjmAgC9AQAWAAgJrRjmAgC9AQAAAA==.Santose:BAAALgAECgIJAgAAAA==.Sarya:BAAALgAECgQJBAABLgAECgkJAgADAAAAAA==.',
Sc='Scalyt:BAAALgADCgYJBgAAAA==.Scerra:BAABLgAECn8mAAISAAkJExBnTgDXAQASAAkJExBnTgDXAQAAAA==.Schmerz:BAAALgADCgUJBQAAAA==.Scridderz:BAAALgAECgMJBgAAAA==.',
Se='Sendia:BAAALgADCgQJBAABLgAECgIJAgADAAAAAA==.Sephiros:BAAALgADCgIJAgAAAA==.Seru:BAABLgAECn8WAAIVAAgJfh+9AwAYAgAVAAgJfh+9AwAYAgAAAA==.Seta:BAABLgAECn8bAAIOAAgJ3xNeQwDmAQAOAAgJ3xNeQwDmAQAAAA==.Seviran:BAAALgADCgIJAwAAAA==.',
Sh='Shakeyjams:BAAALgADCgYJBgABLgAFFAIJBgASAL4cAA==.Shamantha:BAAALgADCgEJAQAAAA==.Shamarha:BAABLgAECn8dAAIQAAgJaBoKMwDmAQAQAAgJaBoKMwDmAQAAAA==.Shaolin:BAAALgAECgQJBAAAAA==.Sharriavolf:BAABLgAECn9FAAQKAAkJsCOLQADbAQAKAAcJ1SGLQADbAQAJAAQJ+CMLIABSAQAIAAEJAAB7IwBkAAAAAA==.Shato:BAAALgAECgYJCQAAAA==.Sheoth:BAAALgADCgQJBAAAAA==.Shiori:BAAALgAECgcJEAAAAA==.Shortmedic:BAAALgAECgQJBAAAAA==.Shotzys:BAAALgAECgYJEgAAAA==.Shrieve:BAAALgAECgMJAwAAAA==.Shurg:BAAALgAECgQJBAAAAA==.',
Si='Sicarius:BAAALgADCgcJCgABLgAECgMJBAADAAAAAA==.Siggismund:BAABLgAECn8rAAIBAAkJKguWeAB9AQABAAkJKguWeAB9AQAAAA==.Simichaelton:BAACLgAFFH8OAAIMAAYJxBAxYQAfAQAMAAYJxBAxYQAfAQAuAAQKfx0AAgwACQkYG1ZJAP8BAAwACQkYG1ZJAP8BAAAA.Sinpal:BAABLgAFFH8LAAIBAAQJYBPRLACkAAABAAQJYBPRLACkAAAAAA==.Sinthea:BAAALgAECgkJAgAAAA==.Sioce:BAAALgADCgkJKwAAAA==.',
Sk='Skrobifu:BAAALgADCgQJAwAAAA==.',
Sl='Slickacitic:BAAALgAECgYJBwABLgAECgcJHwAQAAwLAA==.Slimselect:BAAALgADCgMJAwAAAA==.Slimt:BAAALgADCgMJAwAAAA==.Sloppyshids:BAAALgAECgcJCAAAAA==.Slur:BAAALgADCgIJAgABLgAECgIJBgADAAAAAA==.',
Sm='Smorroy:BAAALgADCgYJBgAAAA==.',
So='Softbakedhoj:BAABLgAECn8eAAIBAAgJ/BxdSQAGAgABAAgJ/BxdSQAGAgAAAA==.Sophrosyne:BAABLgAECn8vAAIVAAkJjRvfLwAdAgAVAAkJjRvfLwAdAgAAAA==.Souless:BAAALgAECgYJBgAAAA==.',
Sp='Spankie:BAAALgAECgUJCAAAAA==.Sparkness:BAAALgAECgMJAwAAAA==.Spartaaxd:BAABLgAECn8yAAIaAAkJkRDmAgAHAQAaAAkJkRDmAgAHAQAAAA==.Spookems:BAAALgAECgIJAgABLgAFFAMJAwADAAAAAA==.Spycy:BAABLgAECn8UAAIMAAkJ3BA3hQBtAQAMAAkJ3BA3hQBtAQAAAA==.',
St='Stabbard:BAAALgADCgMJAwAAAA==.Stagerrind:BAAALgAECgUJDQAAAA==.Starfall:BAAALgAECgkJAgAAAA==.Steiner:BAABLgAECn8qAAMGAAkJOwzhNAB+AQAGAAkJOwzhNAB+AQABAAEJ9QcBtgEnAAAAAA==.Stinkyfrog:BAACLgAFFH8GAAIBAAMJxQzshgClAAABAAMJxQzshgClAAAuAAQKfyUAAgEACQlQIuALAAYDAAEACQlQIuALAAYDAAAA.Stovetop:BAAALgAECgEJAQABLgAECgUJBwADAAAAAA==.Stubmcbean:BAAALgADCggJCQABLgAECgkJPwAfAO8HAA==.Stunted:BAAALgAECgMJAwAAAA==.',
Su='Sugarfrost:BAABLgAECn8mAAIMAAkJOgs5pAA0AQAMAAkJOgs5pAA0AQAAAA==.Sugarseer:BAAALgAECgQJBAABLgAECgkJJgAMADoLAA==.Suka:BAAALgAECgUJEAAAAA==.Surok:BAAALgAECgYJDwAAAA==.',
Sw='Sweetleaf:BAAALgAECgUJCAAAAA==.Swiftleaf:BAAALgAECgcJDAAAAA==.',
Sy='Sylentcurse:BAABLgAECn8oAAIIAAgJfQ4KAgAzAQAIAAgJfQ4KAgAzAQABLgAECgkJKAAVABYSAA==.Sylentstorm:BAABLgAECn8cAAMQAAgJYwPKgwDXAAAQAAgJYwPKgwDXAAAjAAEJAAAHyQAAAAABLgAECgkJKAAVABYSAA==.Syleta:BAABLgAECn9LAAQYAAkJKiCaBADjAgAYAAkJ3h+aBADjAgAVAAcJwxwNMADwAQAZAAYJCRNpRABEAQABLgAECgIJAgADAAAAAA==.',
Ta='Tabraxis:BAAALgAECgEJAQAAAA==.Tagalorc:BAABLgAECn8fAAMlAAkJPRVFAwD2AQAlAAkJPRVFAwD2AQAMAAEJ8QGigQEcAAAAAA==.Takamaki:BAAALgAECgEJAwAAAA==.Tanksbacon:BAABLgAECn8oAAMBAAkJgBnKMAA9AgABAAkJgBnKMAA9AgACAAQJtxKSLwCWAAAAAA==.Taylith:BAAALgAECgYJEgAAAA==.',
Te='Teana:BAACLgAFFH8GAAIaAAMJqgePCQC8AAAaAAMJqgePCQC8AAAuAAQKfyIAAhoACAnkD5MQAG0BABoACAnkD5MQAG0BAAAA.Teannev:BAAALgADCgYJBgAAAA==.Tempestas:BAAALgAECgEJAQAAAA==.Teraax:BAAALgADCgEJAQAAAA==.',
Th='Tharos:BAAALgAECgUJCgAAAA==.Thebrewco:BAAALgADCgMJAwABLgAFFAUJEgAWANYSAA==.Thechadd:BAABLgAFFH8HAAIjAAcJaAPhNwCvAAAjAAcJaAPhNwCvAAAAAA==.Thelegendáry:BAACLgAFFH8QAAIQAAQJlxR8GgC6AAAQAAQJlxR8GgC6AAAuAAQKfxoAAhAABgmWF0FKAFkBABAABgmWF0FKAFkBAAAA.Thetool:BAAALgAECgMJBAAAAA==.Thevileone:BAAALgAECggJCAABLgAFFAQJGQARAJgdAA==.Thraine:BAAALgAECgYJCwAAAA==.',
Ti='Tinyshadowz:BAAALgAECgEJAQAAAA==.Tione:BAABLgAECn87AAMgAAkJQhz+EgA9AgAgAAgJMh3+EgA9AgAWAAkJFQuXVAA+AQAAAA==.Tireck:BAAALgADCggJCQAAAA==.',
To='Toriee:BAAALgAECgkJCQAAAA==.Tormented:BAAALgAECgMJAwAAAA==.Totembish:BAABLgAECn8gAAIjAAkJZAnaPABCAQAjAAkJZAnaPABCAQAAAA==.',
Tr='Treebear:BAAALgADCgcJDQAAAA==.Tremor:BAAALgAECgEJAgAAAA==.Trisstan:BAABLgAECn8uAAMMAAkJYgtlkgBTAQAMAAkJYgtlkgBTAQApAAMJawEvDQBVAAAAAA==.Trucknly:BAAALgADCgMJAwAAAA==.',
Tu='Tundarian:BAAALgAECggJDwAAAA==.Tundie:BAAALgAFFAEJAQAAAA==.',
Tw='Twigz:BAAALgADCgcJBgAAAA==.',
Ty='Tyronicals:BAABLgAECn8iAAMMAAkJshvsOwAqAgAMAAkJkBjsOwAqAgAlAAUJHyAJBgDAAQAAAA==.Tyster:BAACLgAFFH8VAAIBAAUJyRSkEwAYAQABAAUJyRSkEwAYAQAuAAQKfyMAAwEACQl0FSBEAPoBAAEACQnGFCBEAPoBAAIAAQkbFgNKAEEAAAAA.',
['Tø']='Tørmëntëd:BAAALgAECgMJBAAAAA==.',
Ug='Ugotdusted:BAAALgADCgYJBgAAAA==.',
Uk='Ukyo:BAAALgADCgUJBgAAAA==.',
Ul='Ullidon:BAAALgAECgIJAgAAAA==.',
Um='Umbrã:BAAALgADCgEJAQAAAA==.',
Un='Unavoidably:BAAALgADCgIJAgAAAA==.Undol:BAAALgADCggJGwABLgAECgkJPwAfAO8HAA==.',
Ux='Uxe:BAAALgAFFAEJAQABLgAECgkJJAAnAFkaAA==.',
Uz='Uzu:BAABLgAECn8kAAMnAAkJWRqeJQCBAQAnAAkJWRqeJQCBAQATAAEJyhLTjQBDAAAAAA==.',
Va='Valios:BAAALgADCgcJBwAAAA==.Valorr:BAAALgAECgQJBAAAAA==.Vamp:BAABLgAECn8YAAIQAAgJxxbxLwDIAQAQAAgJxxbxLwDIAQAAAA==.Vandaldor:BAAALgAECgYJEQAAAA==.Vandrana:BAAALgAECgUJCQAAAA==.Vasalrius:BAAALgADCgIJAgAAAA==.Vasilli:BAAALgADCgYJDwAAAA==.',
Ve='Vedrix:BAAALgAECgcJBgAAAA==.Vellora:BAAALgADCgUJBQAAAA==.Veloth:BAACLgAFFH8dAAIMAAQJYhkEUAA+AQAMAAQJYhkEUAA+AQAuAAQKfzMAAgwACQnwIh4iAJUCAAwACQnwIh4iAJUCAAAA.Vexnyx:BAAALgADCgcJCAAAAA==.',
Vh='Vhitahni:BAAALgAECgMJAwAAAA==.',
Vi='Viggle:BAAALgADCggJCAABLgAECgkJNwACAJwiAA==.Vireaux:BAAALgADCgEJAQAAAA==.Viviro:BAAALgADCgcJDQAAAA==.',
Vl='Vll:BAABLgAECn8nAAMVAAkJtRsKKQA6AgAVAAkJtRsKKQA6AgAYAAIJewTpKgBVAAABLgAECggJIgALAO4iAA==.',
Vo='Voodoomike:BAAALgAECgIJAgAAAA==.',
Vy='Vynlorin:BAAALgAECgYJBgABLgAECgkJMgABAFQgAA==.',
Wa='Wanawa:BAAALgAECgMJAwABLgAECgkJIgAXABwVAA==.Wanghaf:BAAALgAECgYJDQAAAA==.Warhorne:BAAALgAECgEJAQABLgAECgkJIgAXABwVAA==.Warloque:BAAALgAECgMJAwAAAA==.Warthog:BAAALgADCgkJGQAAAA==.Waterbender:BAABLgAECn8ZAAIQAAkJRRqPGQB+AgAQAAkJRRqPGQB+AgAAAA==.',
We='Weechuup:BAAALgAECgMJAwAAAA==.Weleindon:BAAALgADCgMJAwAAAA==.',
Wi='Wifeotusk:BAAALgAECgkJEAAAAA==.Wiggle:BAAALgADCgMJAwAAAA==.Willmar:BAABLgAECn8hAAIBAAgJ2hY3UQDVAQABAAgJ2hY3UQDVAQAAAA==.Wilshaman:BAAALgAECggJDAAAAA==.Window:BAAALgADCgUJBQABLgAECgcJIAAOAKYeAA==.',
Wm='Wmdplague:BAAALgADCgYJBgAAAA==.',
Wo='Wolf:BAABLgAECn8vAAIEAAkJPhn9AQCqAQAEAAkJPhn9AQCqAQAAAA==.Wolfton:BAAALgAECgMJAwAAAA==.Woodtique:BAAALgAECgMJBgAAAA==.',
Wr='Wrekkit:BAAALgAECgkJEQAAAA==.',
Wy='Wylian:BAAALgAECgIJAgAAAA==.',
Xa='Xaeri:BAAALgADCgMJBAAAAA==.Xameris:BAAALgADCgEJAQAAAA==.Xandercruise:BAABLgAECn8UAAMVAAgJIhvAHQBTAgAVAAgJIhvAHQBTAgAZAAMJrAJgdABtAAAAAA==.',
Xe='Xelgoth:BAAALgADCgcJBgAAAA==.Xelphie:BAAALgADCgUJBQAAAA==.',
Xi='Xiia:BAAALgAECgIJAgABLgAECgQJBQADAAAAAA==.',
Xu='Xuchilbara:BAABLgAECn8eAAIXAAgJuRojCwALAgAXAAgJuRojCwALAgAAAA==.',
Xy='Xyro:BAAALgAECgUJBQABLgAFFAMJBQASAAwRAA==.',
Ya='Yamato:BAAALgAECgcJDQAAAA==.',
Za='Zaledron:BAABLgAECn8jAAISAAgJcCAMBgCJAQASAAgJcCAMBgCJAQAAAA==.Zapnasty:BAAALgADCgcJBgAAAA==.',
Ze='Zenno:BAABLgAECn8sAAMfAAkJBxOwEACoAQAfAAkJBxOwEACoAQAQAAMJVgiBtgBeAAAAAA==.Zevorcia:BAAALgAECgMJAwAAAA==.',
Zh='Zhades:BAACLgAFFH8kAAMSAAUJXB1xGgBBAQASAAUJXB1xGgBBAQAaAAMJ/RUABwDpAAAuAAQKf0YAAxIACQmiJY8HADkDABIACQmiJY8HADkDABoACAlQIf0DAJcCAAAA.Zhandaria:BAAALgAECgQJBwAAAA==.Zhandraia:BAAALgADCgUJBQAAAA==.Zhort:BAAALgAECgIJAwAAAA==.Zhulodok:BAAALgADCgMJAwAAAA==.',
Zi='Zioki:BAAALgAECgMJBAAAAA==.',
Zm='Zmrfister:BAAALgAECgYJBgABLgAFFAUJJAASAFwdAA==.',
Zo='Zodgul:BAAALgAECgQJBAAAAA==.Zomby:BAABLgAFFH8IAAISAAMJXA6KpwDMAAASAAMJXA6KpwDMAAABLgAFFAYJDgAMAMQQAA==.',
Zp='Zpersephone:BAABLgAECn8cAAIKAAcJDxMjaQBqAQAKAAcJDxMjaQBqAQABLgAFFAUJJAASAFwdAA==.',
Zr='Zrii:BAAALgAECggJDQAAAA==.',
Zu='Zultan:BAACLgAFFH8RAAIKAAQJawfsaADzAAAKAAQJawfsaADzAAAuAAQKf0MAAwoACQnKGfQDAK8BAAoACQnKGfQDAK8BAAkAAglmBBtIABkAAAAA.Zurrik:BAACLgAFFH8LAAMgAAQJTwYRMQC+AAAgAAQJEgQRMQC+AAAEAAMJYQZ/KgBxAAAuAAQKfz4AAyAACQm0EuggAMIBACAACQnwEeggAMIBAAQAAgn+E0NNAHcAAAAA.',
Zy='Zynofhealth:BAAALgADCgUJAwAAAA==.',
['Çõ']='Çõîñflïp:BAAALgADCgcJHAAAAA==.',
['Ðr']='Ðream:BAACLgAFFH8GAAInAAMJqBTYEgDjAAAnAAMJqBTYEgDjAAAuAAQKfycAAycACAmEHzsJAPUCACcACAmEHzsJAPUCABMAAwkjGQ2ZADYAAAAA.',
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
