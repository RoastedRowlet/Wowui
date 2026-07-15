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

local lookup = {'Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Druid-Guardian','Priest-Discipline','Paladin-Holy','Warrior-Fury','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','DemonHunter-Havoc','Mage-Frost','Druid-Balance','Druid-Restoration','DemonHunter-Vengeance','DemonHunter-Devourer','Monk-Mistweaver','Shaman-Restoration','DeathKnight-Blood','DeathKnight-Unholy','Monk-Windwalker','Warrior-Protection','Hunter-BeastMastery','Druid-Feral','Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Evoker-Augmentation','Evoker-Preservation','Priest-Holy','Shaman-Enhancement','DeathKnight-Frost','Warrior-Arms','Priest-Shadow','Shaman-Elemental','Rogue-Outlaw','Mage-Arcane','Rogue-Assassination','Monk-Brewmaster','Evoker-Devastation','Mage-Fire',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=46,date='2026-07-12',data={Ab='Abberleigh:BAAALgAFFAMJAwAAAA==.',
Ad='Adonya:BAAALgADCgIJAQAAAA==.',
Ae='Aelgagar:BAAALgAECgYJEAAAAA==.Aelirina:BAAALgAECgMJAwAAAA==.',
Ah='Ahamay:BAAALgADCgEJAgAAAA==.',
Ai='Ailde:BAAALgADCgkJDgAAAA==.',
Ak='Akshhan:BAABLgAFFH8IAAIBAAUJlxBKSQAaAQABAAUJlxBKSQAaAQAAAA==.',
Al='Alania:BAAALgADCgYJCAAAAA==.Alaraa:BAABLgAECn8mAAMCAAgJLB4WCQBCAgACAAgJLB4WCQBCAgABAAIJ4xVQMwF7AAABLgAECgIJAgADAAAAAA==.Alarlia:BAABLgAECn8jAAIEAAgJvgtkMQDlAAAEAAgJvgtkMQDlAAAAAA==.Alathor:BAAALgAECgEJAQAAAA==.Algonq:BAABLgAECn8dAAIFAAYJdwO3DACvAAAFAAYJdwO3DACvAAABLgAECgkJOgAGABIGAA==.Alliesofevil:BAABLgAECn8nAAIHAAkJbBU+JgDGAQAHAAkJbBU+JgDGAQAAAA==.Allsar:BAABLgAECn8aAAIEAAkJnB07BgCeAgAEAAkJnB07BgCeAgAAAA==.Alsar:BAAALgAECgQJBwABLgAECgkJGgAEAJwdAA==.Alssar:BAAALgAECgYJCwAAAA==.Alstar:BAAALgAECgEJAgAAAA==.',
Am='Amaraa:BAAALgAECgMJAwAAAA==.Amathus:BAACLgAFFH8QAAQIAAUJhQ7NAwDgAAAIAAMJxRDNAwDgAAAJAAQJywRzEACwAAAKAAMJ1gT5iwCtAAAuAAQKf3MABAkACQlmGgcEAEgCAAkACQkaGgcEAEgCAAoACQnFFGtGAMcBAAgABgm3E5wDAAABAAAA.Amaunet:BAAALgADCgUJBQAAAA==.Amentia:BAAALgAECgQJBAAAAA==.',
An='Anahilis:BAAALgADCgcJCAAAAA==.Andarial:BAABLgAECn8bAAILAAkJDQ/lJwA9AQALAAkJDQ/lJwA9AQAAAA==.Andella:BAAALgAECgIJAgAAAA==.Andreth:BAABLgAECn8WAAIMAAgJ3QddxwD+AAAMAAgJ3QddxwD+AAAAAA==.Anoxyn:BAAALgAECgcJCQAAAA==.Anthe:BAABLgAECn8dAAMNAAcJ6w4WBgAiAQANAAcJ6w4WBgAiAQAOAAIJwgUDGQA1AAAAAA==.Anzul:BAABLgAECn8yAAMBAAkJVCCUJAByAgABAAkJQh+UJAByAgACAAUJxB0TGgBIAQAAAA==.',
Ar='Araestirra:BAABLgAECn8zAAMJAAcJmBK0AgAwAQAJAAYJzBS0AgAwAQAKAAcJBgc4qwDsAAAAAA==.Arcanmaggy:BAAALgADCgkJHgABLgAFFAYJHgAKAFIEAA==.Ardahh:BAAALgADCgQJBAAAAA==.Arnold:BAABLgAECn8XAAMPAAgJ6hSYCwCjAQAPAAgJ6hSYCwCjAQAQAAEJagPLOgEbAAABLgAECgkJGgAEAJwdAA==.Arntdorn:BAAALgADCgEJAQAAAA==.Arroes:BAABLgAECn8ZAAIRAAgJGB/qFgBiAgARAAgJGB/qFgBiAgAAAA==.',
As='Asahna:BAAALgAECgQJBAAAAA==.',
At='Atlas:BAAALgAECggJCgABLgAECgkJGgAEAJwdAA==.',
Au='Aurrell:BAAALgADCgcJBwAAAA==.',
Av='Avoid:BAAALgAECgMJAwAAAA==.',
Ay='Ayroona:BAABLgAECn8pAAISAAkJOgpVTgB4AQASAAkJOgpVTgB4AQAAAA==.',
Az='Azhol:BAAALgAECgQJBAAAAA==.',
Ba='Bacontotem:BAAALgADCgMJBQAAAA==.Baelhal:BAACLgAFFH8ZAAITAAQJmB08FQBEAQATAAQJmB08FQBEAQAuAAQKfzQAAhMACQmaHUIOACYCABMACQmaHUIOACYCAAAA.Balka:BAAALgADCgYJCAAAAA==.Barbaydos:BAAALgADCggJCQAAAA==.Barenjager:BAAALgAECgEJAQAAAA==.Basement:BAABLgAECn8gAAIQAAcJph4mMQABAgAQAAcJph4mMQABAgAAAA==.',
Be='Beastnite:BAAALgADCgkJKQABLgAECgkJGwAUANANAA==.Bellaburger:BAABLgAFFH8IAAIVAAQJsgYfIgDOAAAVAAQJsgYfIgDOAAAAAA==.Bellissidan:BAAALgAECgEJAwAAAA==.Benedin:BAAALgAECgYJEQABLgAECgkJRgAIALYgAA==.',
Bi='Bigpapapete:BAAALgAECgYJAwAAAA==.Bigtex:BAABLgAECn81AAMHAAkJewuiCAABAQAHAAkJRwuiCAABAQAWAAMJgwzKPAB/AAAAAA==.Biped:BAABLgAECn8zAAIIAAkJPhNbCADkAQAIAAkJPhNbCADkAQAAAA==.Birill:BAAALgAECgEJAgAAAA==.Bishul:BAAALgAECggJCQAAAA==.',
Bl='Blackdeath:BAACLgAFFH8FAAIUAAIJSgmG6wB+AAAUAAIJSgmG6wB+AAAuAAQKfzMAAhQACQkjHagIAGUBABQACQkjHagIAGUBAAAA.',
Bo='Bombarian:BAAALgAECgUJCwAAAA==.Bone:BAAALgAECgEJAQAAAA==.Boomstique:BAABLgAECn9EAAIXAAkJnB5xAgCfAgAXAAkJnB5xAgCfAgAAAA==.Boondocka:BAABLgAECn82AAIXAAkJ9BqFHAB6AgAXAAkJ9BqFHAB6AgAAAA==.',
Br='Brewco:BAACLgAFFH8TAAMOAAUJ1hLaLQD9AAAOAAUJ1hLaLQD9AAAYAAEJzRuNCwBSAAAuAAQKfzkABA4ACQkEHKYUAJACAA4ACQkEHKYUAJACABgABgnDG1YSAJYBAAQABQl6Dw49ALIAAAAA.Brewer:BAAALgAECgEJAQAAAA==.Brickmebtch:BAAALgAFFAEJAQAAAA==.Bruda:BAAALgAECgIJAwAAAA==.Brutalís:BAABLgAECn8pAAIXAAkJOhICPwDmAQAXAAkJOhICPwDmAQABLgAECgkJLAAIAJYNAA==.',
Bt='Btrain:BAABLgAECn8hAAMCAAYJ3AqaMQCfAAABAAYJzQZa9ADFAAACAAUJgAyaMQCfAAAAAA==.',
['Bó']='Bóunty:BAABLgAECn8bAAQZAAcJwx8lHwCjAQAZAAcJrh0lHwCjAQAXAAQJNx5HXgBNAQAaAAEJPgJtmAAeAAAAAA==.',
Ca='Camaryn:BAAALgADCgIJAgAAAA==.Canadia:BAAALgAECgQJBgAAAA==.Caritta:BAAALgAECgQJBAAAAA==.Catdaddan:BAAALgADCgYJBgAAAA==.Cattnip:BAAALgAECgEJAQAAAA==.Cavisch:BAABLgAECn9GAAMIAAkJtiAcAQD/AgAIAAkJtiAcAQD/AgAKAAkJWBi7OwDsAQAAAA==.',
Ce='Cedric:BAAALgAECgIJAgABLgAECgcJCQADAAAAAA==.Cenobité:BAAALgAFFAEJAQAAAQ==.Cerr:BAAALgAECgMJBAAAAA==.',
Ch='Chamber:BAAALgAECgYJCAABLgAECgcJIAAQAKYeAA==.Chantilly:BAAALgADCgYJDwAAAA==.Chaosmaster:BAAALgAECgMJAwAAAA==.Chardee:BAABLgAFFH8HAAIbAAMJlBUmDQAVAQAbAAMJlBUmDQAVAQAAAA==.Charmeleon:BAABLgAECn8UAAMcAAgJCRJ1QQAjAQAcAAgJCRJ1QQAjAQAdAAIJfAwbNABWAAAAAA==.Charmin:BAAALgADCgUJBQAAAA==.Chicka:BAAALgAECgIJAgABLgAECgYJCQADAAAAAA==.Chiff:BAAALgADCgUJAwAAAA==.Chilledog:BAAALgADCgQJBAAAAA==.Chip:BAAALgAECgMJBgAAAA==.Churg:BAAALgAECgEJAQAAAA==.',
Ci='Cirax:BAABLgAECn8qAAIXAAgJdBcvPgDpAQAXAAgJdBcvPgDpAQAAAA==.Cirin:BAAALgADCgEJAQAAAA==.Citruscoolin:BAAALgAECgEJAQAAAA==.',
Cl='Cleetess:BAAALgAECgEJAQAAAA==.Clenton:BAABLgAECn95AAMCAAkJNw2tAwAzAQACAAkJ1gutAwAzAQABAAgJCQhFrwAgAQAAAA==.Clipper:BAAALgADCgYJBgAAAA==.',
Co='Cobrakai:BAAALgAECgIJAgAAAA==.Comeatmebro:BAAALgAECgkJDgABLgAFFAQJGAAeAL8eAA==.Cowboyup:BAAALgADCgYJBgAAAA==.',
Cr='Crichton:BAACLgAFFH8UAAIQAAQJ9Rl5PgAtAQAQAAQJ9Rl5PgAtAQAuAAQKfzIAAhAACQm0IYIMAOECABAACQm0IYIMAOECAAAA.Cronnan:BAAALgAECgUJBQAAAA==.Crowford:BAABLgAECn82AAIXAAkJPRNiDwAuAQAXAAkJPRNiDwAuAQAAAA==.',
Cy='Cyris:BAAALgAECgYJCwABLgAECgkJRAAfADcJAA==.',
['Cá']='Cástle:BAAALgAECgEJAQABLgAECgcJIAAQAKYeAA==.',
Da='Daemonfaust:BAAALgAECgYJDwAAAA==.Daevahna:BAAALgADCgYJBgAAAA==.Dahtty:BAAALgAECgYJBwAAAA==.Dak:BAABLgAECn8bAAIBAAgJjRhqTwDzAQABAAgJjRhqTwDzAQABLgAFFAMJBQAUAAwRAA==.Dakdeekay:BAACLgAFFH8FAAIUAAMJDBEeOgDVAAAUAAMJDBEeOgDVAAAuAAQKfyUAAhQACQlbF7UwADwCABQACQlbF7UwADwCAAAA.Daksclaw:BAAALgAFFAIJAgABLgAFFAMJBQAUAAwRAA==.Daksmash:BAAALgAECgUJCAABLgAFFAMJBQAUAAwRAA==.Dakstab:BAAALgADCgkJCQAAAA==.Dalsar:BAABLgAECn8UAAMEAAgJywfxNwDHAAAEAAgJywfxNwDHAAAOAAQJKAnHDQCCAAAAAA==.Darkbrew:BAAALgADCgYJCAABLgAECgkJPwACAJwiAA==.Darkfes:BAAALgAECgEJAQAAAA==.Darkmiza:BAACLgAFFH8eAAIKAAYJUgRnbgDlAAAKAAYJUgRnbgDlAAAuAAQKfzsAAwoACAl1EVJlAHMBAAoACAl1EVJlAHMBAAkAAglDC0lYAGYAAAAA.Darkseer:BAAALgAFFAIJBAAAAA==.Darthbluto:BAAALgAECgUJDQABLgAECgYJDwADAAAAAA==.Dasham:BAAALgAECgQJBAAAAA==.Daymann:BAABLgAECn8iAAIBAAkJHRa8SQDpAQABAAkJHRa8SQDpAQAAAA==.',
De='Deadazz:BAAALgADCgYJCgAAAA==.Deadmangalad:BAABLgAECn80AAMgAAkJQw6LAgBHAQAgAAkJQw6LAgBHAQATAAEJFATyaQAWAAAAAA==.Deathnotes:BAAALgADCgEJAQAAAA==.Deathquina:BAAALgAECgMJAwAAAA==.Deathtickle:BAAALgAECgcJAwAAAA==.Deedees:BAABLgAECn8eAAINAAgJ5QZ8QwD/AAANAAgJ5QZ8QwD/AAAAAA==.Demonbo:BAACLgAFFH8GAAIQAAIJvQ/xNQBzAAAQAAIJvQ/xNQBzAAAuAAQKfxoAAhAACAmIFBRkAF8BABAACAmIFBRkAF8BAAAA.Demondrink:BAAALgAECgQJBgAAAA==.Demonhandler:BAAALgADCggJDwAAAA==.Deo:BAACLgAFFH8YAAMHAAQJGiDkEQB4AQAHAAQJGiDkEQB4AQAhAAMJMBTPKADKAAAuAAQKfz8AAwcACQkmJAAEACYDAAcACQkmJAAEACYDACEAAgmSDeVjAFoAAAAA.Depression:BAAALgADCgUJBQAAAA==.Derpixion:BAABLgAECn8tAAMXAAgJYhlFJwAcAgAXAAgJYhlFJwAcAgAZAAUJYQtJPgDSAAAAAA==.Dessirius:BAAALgAECgEJAQAAAA==.Dethphalanax:BAAALgADCgUJCQAAAA==.',
Di='Digbie:BAAALgADCgYJBwAAAA==.Digs:BAAALgADCgMJAwAAAA==.Dirtnåp:BAAALgAECgYJEwAAAA==.Diskbänk:BAAALgAECgUJBwAAAA==.',
Dk='Dkho:BAACLgAFFH8FAAIMAAMJ7gNqkwCuAAAMAAMJ7gNqkwCuAAAuAAQKfxUAAgwACAnCDbV/AHgBAAwACAnCDbV/AHgBAAAA.',
Dr='Drago:BAAALgAECgEJBAAAAA==.Dragontoast:BAAALgAECggJEgAAAA==.Dral:BAEALgADCgkJKAAAAA==.Draygun:BAAALgAECgcJBwABLgAFFAQJGAAHABogAA==.Drphilyobody:BAABLgAECn8cAAIUAAcJCQhMsgARAQAUAAcJCQhMsgARAQAAAA==.Drui:BAABLgAECn8dAAINAAgJsQ4dNgBkAQANAAgJsQ4dNgBkAQAAAA==.Druidïan:BAAALgAECgQJBQAAAA==.',
Du='Duelittle:BAABLgAECn8qAAIiAAcJmQ05CQDdAAAiAAcJmQ05CQDdAAAAAA==.',
Dy='Dynwor:BAAALgAECgEJAgAAAA==.',
['Dé']='Dérailed:BAAALgAECgUJEgAAAA==.',
['Dî']='Dîz:BAAALgADCgEJAQAAAA==.',
Ea='Easme:BAABLgAECn8uAAMZAAkJBw0sAwBAAQAZAAkJBw0sAwBAAQAaAAUJRANPYgC3AAAAAA==.Eatmyfrontal:BAABLgAECn87AAIMAAkJQBoAPwAgAgAMAAkJQBoAPwAgAgAAAA==.',
Eb='Ebbola:BAAALgADCgcJDgAAAA==.Ebon:BAAALgAECgMJAwABLgAECggJDAADAAAAAA==.',
Eh='Ehsinat:BAAALgADCgYJBgAAAA==.',
El='Elaraa:BAAALgAECgYJBwAAAA==.Elaric:BAAALgAECgcJCQAAAA==.Elger:BAAALgADCgEJAgAAAA==.Elvi:BAAALgAECgEJAQAAAA==.',
Em='Emory:BAAALgADCgEJAQAAAA==.',
En='Engi:BAAALgAECgcJDgAAAA==.',
Ep='Epikrate:BAABLgAECn8fAAMKAAgJURl8QADbAQAKAAcJIRl8QADbAQAJAAMJ4hiqSACUAAAAAA==.',
Es='Escaper:BAABLgAECn84AAIgAAkJcxLOCwC7AQAgAAkJcxLOCwC7AQAAAA==.',
Ex='Extrema:BAAALgAECggJEgAAAA==.',
Ez='Ezsdruid:BAAALgAECgkJCQAAAA==.',
Fa='Faesha:BAAALgAECgEJAQAAAA==.Fallenash:BAAALgADCgMJAwABLgAFFAQJFgAMAGsfAA==.Fallenembers:BAACLgAFFH8WAAIMAAQJax/0QwBhAQAMAAQJax/0QwBhAQAuAAQKfzsAAgwACQlJJb8GAEsDAAwACQlJJb8GAEsDAAAA.Famine:BAABLgAECn8dAAMUAAgJ0AWlvAACAQAUAAgJwwSlvAACAQAgAAUJzAf7DADfAAAAAA==.Farquaadtwo:BAAALgAECgIJAgAAAA==.',
Fe='Fearofthdark:BAAALgADCgEJAQAAAA==.',
Ff='Fflar:BAAALgADCgUJBQABLgAECgkJAwADAAAAAA==.',
Fh='Fhait:BAABLgAECn8hAAMFAAYJxBRGBACUAQAFAAYJxBRGBACUAQAiAAYJZwVODQCfAAABLgAECgkJQAAVAMAPAA==.',
Fi='Firsttimepvp:BAACLgAFFH8HAAIbAAIJJg3xNQCJAAAbAAIJJg3xNQCJAAAuAAQKfx4AAhsACQnaE6kUAPwBABsACQnaE6kUAPwBAAAA.',
Fl='Flow:BAAALgADCgYJBgAAAA==.',
Fr='Frenchtoast:BAAALgAECgIJAgAAAA==.Frostyflaker:BAAALgAECgUJDAAAAA==.',
Ga='Gaiã:BAAALgADCgEJAgAAAA==.Galadan:BAABLgAECn8jAAMEAAkJ5wsICQC4AAAEAAYJIA0ICQC4AAAYAAgJywZuCgBeAAABLgAECgkJNAAgAEMOAA==.Garrekton:BAAALgADCgIJAgABLgAECgkJRgAIALYgAA==.Gaskelmarg:BAAALgAECgUJDwAAAA==.',
Ge='Gellane:BAAALgAECgMJAwAAAA==.',
Gh='Ghosty:BAABLgAECn8hAAQFAAkJIRWWHwDRAQAFAAkJsRGWHwDRAQAeAAcJpAuKTgD+AAAiAAEJcAEanAAXAAAAAA==.Ghuun:BAAALgADCgEJAgABLgAFFAMJCAARAAoMAA==.',
Gi='Gigaweed:BAABLgAFFH8IAAIRAAMJCgx/RQCOAAARAAMJCgx/RQCOAAAAAA==.',
Go='Goblinlayer:BAAALgAECgYJEwAAAA==.Goldtusk:BAABLgAECn8iAAIYAAkJHBVbDgDQAQAYAAkJHBVbDgDQAQAAAA==.Gooey:BAAALgADCggJDgAAAA==.Gostann:BAABLgAECn8mAAIKAAkJlRclJwBAAgAKAAkJlRclJwBAAgAAAA==.',
Gr='Grayparser:BAAALgADCgYJCQAAAA==.Grimsly:BAAALgAECgEJAQAAAA==.Grundler:BAAALgAFFAEJAQAAAA==.Gryphone:BAAALgADCgkJEAAAAA==.',
Gu='Gurinendo:BAAALgAECgEJAgAAAA==.Gustwin:BAAALgAECgQJBgAAAA==.',
['Gà']='Gàins:BAAALgAECgMJAwABLgAECgkJPwACAJwiAA==.',
Ha='Hakmud:BAAALgADCgYJCwAAAA==.Halsin:BAAALgADCgMJAwABLgAECggJIQAjAD0aAA==.Hamshammy:BAAALgAECgEJAQAAAA==.',
He='Heftydin:BAAALgAECgMJCQAAAA==.Heftymists:BAAALgAECgUJBQAAAA==.Heftystomp:BAAALgADCgUJBQAAAA==.Heftyvoid:BAAALgADCgEJAQAAAA==.Hela:BAAALgADCgcJBwAAAA==.Hercyderc:BAAALgAECgEJAQABLgAFFAIJBQAQADYgAA==.Hettokal:BAAALgAECgcJCQAAAA==.Heximal:BAAALgAECgEJAQABLgAECgkJNgAXAPQaAA==.Heyitsjimbo:BAAALgADCgUJCQAAAA==.',
Ho='Holierhtanu:BAAALgADCgQJBwAAAA==.Holyhellion:BAABLgAECn8dAAIQAAkJchEFRQC4AQAQAAkJchEFRQC4AQAAAA==.Hondojoe:BAACLgAFFH8YAAIeAAQJvx5lDwBbAQAeAAQJvx5lDwBbAQAuAAQKfzsAAx4ACQnuIEoLAJsCAB4ACQnuIEoLAJsCAAUAAgnYBv1uAE0AAAAA.Honeydrake:BAAALgAECgYJCAAAAA==.Hopewell:BAABLgAECn86AAIGAAkJEgbXCADJAAAGAAkJEgbXCADJAAAAAA==.',
Hu='Huginn:BAAALgADCgEJAQAAAA==.Hugnsnuggle:BAABLgAECn9AAAIPAAkJlw1/AQB9AQAPAAkJlw1/AQB9AQABLgAECgkJQAAVAMAPAA==.Huhu:BAABLgAECn8ZAAIHAAkJrxRhKwCnAQAHAAkJrxRhKwCnAQAAAA==.Huma:BAAALgAECgYJEAABLgAFFAQJCgAXAAAOAA==.Hundreg:BAAALgADCgYJBQAAAA==.',
['Hô']='Hôlydiver:BAAALgAECgIJAgAAAA==.',
Ib='Ibn:BAABLgAECn8sAAIhAAkJBws1HwBkAQAhAAkJBws1HwBkAQAAAA==.',
Ic='Icyhot:BAAALgAECgYJCgAAAA==.',
Id='Ideal:BAAALgADCgYJDAAAAA==.',
Il='Illaris:BAAALgADCgIJAgAAAA==.',
In='Infiniity:BAAALgAECgMJCQAAAA==.Inksmear:BAAALgAECgEJAgAAAA==.',
Ir='Irielle:BAABLgAECn8UAAMOAAYJsxAFCAD4AAAOAAYJsxAFCAD4AAANAAEJAACfHwAAAAAAAA==.',
Is='Ishanllin:BAAALgAECgIJAgAAAA==.',
Iv='Ivarurngamet:BAABLgAECn8iAAIQAAkJyRfaLgALAgAQAAkJyRfaLgALAgAAAA==.Ivylyn:BAAALgAECgkJDgAAAA==.',
Ix='Ixiyá:BAABLgAECn89AAMSAAkJNCNtBABxAwASAAkJNCNtBABxAwAjAAEJzghXrgAqAAAAAA==.Ixií:BAAALgAECgEJAwAAAA==.Ixì:BAABLgAECn8XAAIOAAcJ1x31IQA4AgAOAAcJ1x31IQA4AgAAAA==.',
Ja='Jakbequick:BAAALgAECgEJAQAAAA==.Jakeyprogue:BAAALgAFFAIJAwABLgAFFAIJBgAUAL4cAA==.Jakota:BAAALgADCgkJFAAAAA==.Jakskeleton:BAABLgAECn8fAAITAAgJ2xoYEAAKAgATAAgJ2xoYEAAKAgAAAA==.Jarobus:BAAALgAECgYJDgAAAA==.Jay:BAAALgADCgEJAQAAAA==.Jaynamir:BAAALgAECgYJEwAAAA==.Jayp:BAAALgAECgMJAwAAAA==.',
Jb='Jbernn:BAAALgAECgEJAQAAAA==.',
Je='Jeamica:BAAALgAECgQJBAAAAA==.',
Jo='Joemacho:BAAALgAECgcJEwABLgAFFAQJGAAeAL8eAA==.Joshtee:BAAALgAECgMJBQAAAA==.Joslyn:BAAALgAECgQJBQAAAA==.Jourdan:BAAALgADCgcJDQAAAA==.',
Ju='Judax:BAACLgAFFH8IAAIjAAMJaQ8FNwCyAAAjAAMJaQ8FNwCyAAAuAAQKfz0AAiMACQm0GyUTAFUCACMACQm0GyUTAFUCAAAA.Justagirl:BAABLgAECn9AAAIVAAkJwA9qAgChAQAVAAkJwA9qAgChAQAAAA==.Justiceboyd:BAAALgADCgMJAwAAAA==.Juti:BAAALgAECgYJEQAAAA==.',
Jy='Jymion:BAAALgADCgEJAQAAAA==.',
['Jú']='Júun:BAAALgADCgEJAQAAAA==.',
Ka='Kadooka:BAACLgAFFH8HAAIXAAIJYwwYPQCSAAAXAAIJYwwYPQCSAAAuAAQKfygAAhcACAmkGbMHAK0BABcACAmkGbMHAK0BAAAA.Kahlyn:BAAALgAECgYJCwAAAA==.Kajax:BAABLgAECn8qAAIbAAgJISMwCAANAwAbAAgJISMwCAANAwAAAA==.Kaldaran:BAABLgAECn8YAAQgAAkJjBuyAwAGAQATAAkJ1BnKGwB+AQAgAAMJ3x2yAwAGAQAUAAIJtQTrUwFOAAAAAA==.Kallan:BAAALgAECgYJEAABLgAECgkJPwACAJwiAA==.Kalleigh:BAAALgADCgQJBAABLgAECgkJRAAfADcJAA==.Karen:BAAALgADCgcJHAAAAA==.Karinn:BAAALgADCgEJAQAAAA==.Karne:BAAALgADCgYJBgAAAA==.Katira:BAAALgAECgQJBQAAAA==.Kazarath:BAAALgADCgUJBQAAAA==.',
Ke='Keeganw:BAABLgAECn8fAAMTAAYJThuSJgAfAQATAAYJThuSJgAfAQAUAAEJKRJcOgA5AAAAAA==.Keelay:BAABLgAECn9TAAIGAAkJQiGLAAD2AgAGAAkJQiGLAAD2AgAAAA==.',
Kh='Khyla:BAAALgAECgEJAQAAAA==.',
Ki='Killua:BAAALgADCgYJBgABLgADCgcJCwADAAAAAA==.Kimiko:BAAALgAECgcJEAAAAA==.',
Kl='Klaw:BAAALgAECgQJBAABLgAECggJKgAbACEjAA==.',
Ko='Koffcmorbius:BAAALgAECgYJCQAAAA==.Koriban:BAABLgAECn8lAAIMAAkJaA69aQCoAQAMAAkJaA69aQCoAQAAAA==.Korreban:BAAALgAECgYJBgABLgAECgkJJQAMAGgOAA==.',
Kr='Kra:BAAALgAECgEJAgABLgAFFAMJCAARAAoMAA==.Kraken:BAACLgAFFH8GAAIJAAMJ1hKrDQDIAAAJAAMJ1hKrDQDIAAAuAAQKfysAAgkACQlzIvIAAAUDAAkACQlzIvIAAAUDAAEuAAUUAwkIABEACgwA.Krim:BAAALgADCgYJBgAAAA==.',
Ku='Kubb:BAABLgAECn9EAAIfAAkJNwmdAgBTAQAfAAkJNwmdAgBTAQAAAA==.Kunst:BAAALgADCgEJAQAAAA==.',
Kw='Kweh:BAACLgAFFH8aAAIYAAYJlh+sAQDcAQAYAAYJlh+sAQDcAQAuAAQKfy0AAxgACQk6IxoFAMACABgACQk6IxoFAMACAA0ABQkbDqZGAPEAAAAA.',
Ky='Kytrina:BAAALgAECgEJAQAAAA==.',
['Kê']='Kêlsen:BAAALgAECgUJBwAAAA==.',
La='Lachupacabra:BAAALgAECgEJAQAAAA==.Larrissa:BAABLgAECn8wAAMIAAkJDAhWAwANAQAIAAkJDAhWAwANAQAJAAEJggPhewAlAAAAAA==.Larry:BAABLgAFFH8TAAIQAAYJghRiPgAtAQAQAAYJghRiPgAtAQAAAA==.Laurlynn:BAABLgAECn8XAAMSAAgJ8wjcEQC8AAASAAcJDAbcEQC8AAAjAAYJPgOTEAB1AAAAAA==.Lavina:BAAALgADCgUJBQAAAA==.',
Le='Lenwe:BAAALgAECgYJDQABLgAECgcJLQAeAGwOAA==.Lettuceprey:BAABLgAECn9EAAIeAAkJsw87BQBJAQAeAAkJsw87BQBJAQAAAA==.',
Li='Lierise:BAABLgAECn8ZAAQUAAkJmRuSBAD1AQAUAAcJIxySBAD1AQAgAAUJhhZZAgBTAQATAAUJMxCVPACfAAAAAA==.Lies:BAAALgADCgkJCQAAAA==.Lightsnipe:BAAALgAECgQJBAAAAA==.Lilkelp:BAAALgAECgYJBwAAAA==.Lilspazz:BAAALgADCgMJAwAAAA==.Lithiri:BAAALgAECgUJCgABLgAECggJIwAUAHAgAA==.',
Lo='Lockatute:BAAALgAECgkJEgAAAA==.Lockdeath:BAAALgAECgQJCQAAAA==.Loric:BAAALgADCgkJCQAAAA==.Loxia:BAABLgAECn8XAAIJAAkJxA1yEwAWAQAJAAkJxA1yEwAWAQAAAA==.',
Lu='Lucille:BAACLgAFFH8FAAIMAAEJfAaVXwBCAAAMAAEJfAaVXwBCAAAuAAQKfx8AAgwACAnjEe8RAAoBAAwACAnjEe8RAAoBAAAA.Luckett:BAAALgADCgEJAQAAAA==.Lucrotia:BAAALgADCgQJBAAAAA==.Luukmosh:BAAALgAECgUJCQAAAA==.',
Ma='Maavarra:BAABLgAECn88AAMYAAkJsCI7AAAcAwAYAAkJsCI7AAAcAwAOAAQJLRQ9CQDVAAAAAA==.Madilyons:BAAALgADCgIJAgAAAA==.Madischa:BAAALgAECgcJEQAAAA==.Madshaggy:BAAALgAECgUJBQAAAA==.Magicdance:BAACLgAFFH8JAAIjAAQJxQJnOACtAAAjAAQJxQJnOACtAAAuAAQKfzsAAxIACQmHEUZLAIMBABIACQmHEUZLAIMBACMACQmeCiULAMAAAAAA.Magolthel:BAAALgADCgYJCQAAAA==.Maimgame:BAABLgAECn8WAAIYAAgJchK/CwACAgAYAAgJchK/CwACAgAAAA==.Majicbob:BAABLgAECn8hAAIjAAgJPRoSHgDxAQAjAAgJPRoSHgDxAQAAAA==.Maki:BAABLgAECn8UAAMkAAkJ/BTeEgDcAAAbAAkJ/BRXLwCJAQAkAAUJxRDeEgDcAAAAAA==.Mansion:BAAALgADCgQJBgABLgAECgcJIAAQAKYeAA==.Marilune:BAAALgADCggJCQAAAA==.Marn:BAAALgADCgQJBAAAAA==.Marthran:BAAALgADCgIJAgAAAA==.Maxlin:BAAALgAECgIJAwAAAA==.',
Mc='Mctowlie:BAAALgAECgYJCAAAAA==.',
Me='Mehänemäntä:BAAALgAECggJEgAAAA==.Meldo:BAAALgADCggJDQAAAA==.Mellinessa:BAABLgAECn8aAAMgAAcJqBXJEwBAAQAUAAYJJRKQlABXAQAgAAUJWBXJEwBAAQAAAA==.Mena:BAAALgADCgUJBgAAAA==.Merixa:BAAALgADCgEJAQAAAA==.',
Mf='Mfdkidney:BAAALgAECgIJAgAAAA==.',
Mi='Midou:BAAALgAECgMJAwABLgAFFAQJCQAjAMUCAA==.Minthraxis:BAAALgADCgEJAQAAAA==.Misaun:BAAALgAECgEJAgABLgAECgMJBAADAAAAAA==.Misericorde:BAACLgAFFH8QAAIVAAQJUyTRCACNAQAVAAQJUyTRCACNAQAuAAQKfzwAAhUACQkYJqUBAF0DABUACQkYJqUBAF0DAAAA.Misstreater:BAABLgAECn8nAAMMAAkJBArnDQA2AQAMAAkJmAnnDQA2AQAlAAcJyQYkCgDpAAAAAA==.',
Mo='Momentomori:BAABLgAECn8gAAIKAAkJvghkbwBcAQAKAAkJvghkbwBcAQAAAA==.Monbow:BAAALgAECgMJBwABLgAFFAIJBgAQAL0PAA==.Monocerotis:BAAALgAECgQJBAAAAA==.Morishima:BAACLgAFFH8XAAIbAAQJ6xmoFgBYAQAbAAQJ6xmoFgBYAQAuAAQKf08AAxsACQlkJPcCACIDABsACQlkJPcCACIDACYAAQkJFtklAD0AAAAA.Morthis:BAABLgAECn84AAMaAAkJPhPWAADlAQAaAAkJPhPWAADlAQAZAAMJWgM5WABMAAAAAA==.',
Mt='Mtpoccy:BAAALgADCgYJBgAAAA==.',
Mu='Multipàss:BAAALgADCgcJCgAAAA==.',
My='Mydarling:BAAALgAFFAIJAwAAAA==.Mymoon:BAAALgAECgIJAgAAAA==.Myris:BAACLgAFFH8HAAIUAAMJ7Q+eUQCXAAAUAAMJ7Q+eUQCXAAAuAAQKfzcAAhQACQmKH0cEAAYCABQACQmKH0cEAAYCAAAA.',
Na='Narcan:BAAALgAECgUJDQAAAA==.Naturalchi:BAABLgAECn8wAAMVAAkJByWbAgBCAwAVAAkJiiSbAgBCAwAnAAgJ8x5yDABuAgAAAA==.',
Nb='Nbi:BAAALgAECgEJAQAAAA==.',
Ne='Nefilion:BAABLgAFFH8GAAIUAAIJ7wsI6QB/AAAUAAIJ7wsI6QB/AAAAAA==.Nemas:BAABLgAECn8hAAICAAgJrxnuDgDVAQACAAgJrxnuDgDVAQAAAA==.Neophalanax:BAAALgADCgMJAwAAAA==.Neverleft:BAAALgAECgUJCAAAAA==.Nezin:BAABLgAECn8tAAQcAAkJyhi/AQDWAQAcAAkJiRe/AQDWAQAoAAYJJRNDDwAXAQAdAAIJuQ2jQABlAAAAAA==.',
Ni='Nightrun:BAAALgADCgcJCwAAAA==.Nightrunnêr:BAAALgAECgUJCwABLgAECgkJPwACAJwiAA==.Nineadin:BAACLgAFFH8VAAMBAAQJnwsQWAAAAQABAAQJnwsQWAAAAQAGAAQJLhfFDAD2AAAuAAQKfycAAwYACQmYHU0TAHgCAAYACQmYHU0TAHgCAAEAAgkjHZ0IAa4AAAAA.Nineshots:BAAALgAFFAMJBAABLgAFFAQJFQABAJ8LAA==.Ninetoads:BAAALgAECgcJDQABLgAFFAQJFQABAJ8LAA==.Nirvanas:BAABLgAECn8dAAIYAAgJ/A10HQAeAQAYAAgJ/A10HQAeAQAAAA==.Niyoko:BAAALgADCgcJBwAAAA==.',
No='Nomik:BAABLgAECn8tAAMeAAcJbA6KNwAgAQAeAAcJbA6KNwAgAQAiAAYJ1Qe6YwCMAAAAAA==.Nonah:BAAALgADCgEJAgAAAA==.North:BAAALgAECggJCAAAAA==.',
Nu='Nuke:BAABLgAECn8VAAIXAAQJvBkuFQDwAAAXAAQJvBkuFQDwAAAAAA==.Nullspace:BAABLgAECn8qAAMeAAkJXhq+FAAvAgAeAAkJXhq+FAAvAgAiAAMJAQzHDgCLAAAAAA==.Nunskee:BAAALgAECgQJBAAAAA==.',
['Ní']='Níght:BAABLgAECn86AAMEAAgJqhhYFQCqAQAEAAgJKRdYFQCqAQAYAAEJ3heGDQBHAAAAAA==.',
Oa='Oaken:BAAALgADCgkJCgAAAA==.',
Oc='Occultivated:BAAALgAECgQJBgAAAA==.',
Od='Oddtotem:BAAALgADCgMJAwAAAA==.',
Oh='Ohhk:BAAALgAECgMJAwAAAA==.',
Om='Ommû:BAAALgAECgMJCAAAAA==.',
Op='Op:BAAALgAECgIJAgABLgAFFAMJCAARAAoMAA==.',
Or='Orillar:BAAALgADCgEJAQAAAA==.',
Pa='Pakeydk:BAABLgAFFH8GAAIUAAIJvhxWxgCfAAAUAAIJvhxWxgCfAAAAAA==.Palacia:BAAALgAECggJEQAAAA==.Pancakedealr:BAAALgAECgUJEAAAAA==.Pancakeeater:BAAALgAECgUJCgAAAA==.Pappabeary:BAAALgADCgEJAQAAAA==.',
Pe='Peaches:BAAALgAECgEJAQAAAA==.Peerow:BAAALgADCgMJAwAAAA==.Permelia:BAAALgADCgkJDwAAAA==.Petrichorica:BAABLgAECn8kAAIjAAkJQAMMDgCYAAAjAAkJQAMMDgCYAAAAAA==.Peí:BAAALgAECgEJAQAAAA==.',
Ph='Phatjake:BAAALgADCgYJBgAAAA==.',
Pi='Ping:BAABLgAFFH8GAAIRAAYJ3RSACADbAQARAAYJ3RSACADbAQAAAA==.Pintobeans:BAABLgAECn8XAAIXAAkJlQVJdwBRAQAXAAkJlQVJdwBRAQAAAA==.',
Pl='Plutonix:BAAALgAECgMJBQAAAA==.',
Pr='Preachêr:BAAALgAECgQJCQABLgAECgkJPwACAJwiAA==.Priestorz:BAAALgADCgQJBAAAAA==.Prohteus:BAAALgAECgEJAQABLgAECgMJBQADAAAAAA==.',
Pu='Puuhceew:BAACLgAFFH8GAAIeAAIJIQrBFABXAAAeAAIJIQrBFABXAAAuAAQKfyIAAh4ACQn6DbU2ACUBAB4ACQn6DbU2ACUBAAAA.',
Qu='Quan:BAEALgADCgcJCQABLgADCgkJKAADAAAAAA==.Quelaag:BAAALgADCgQJBAAAAA==.Quenthel:BAAALgAECgkJAwAAAA==.Quiescent:BAABLgAECn8pAAIQAAgJdRr2KQAiAgAQAAgJdRr2KQAiAgAAAA==.Quina:BAAALgAECgQJBwAAAA==.',
Ra='Ragingtides:BAAALgADCgEJAQAAAA==.Rainera:BAABLgAECn8zAAMIAAkJJSW8AQDWAgAIAAkJJSW8AQDWAgAKAAEJAxH1OgE1AAABLgAFFAcJHAAPAPcjAA==.Ramanas:BAABLgAECn8bAAMiAAkJ0BPOLwBgAQAiAAgJVxTOLwBgAQAFAAYJnBGILQAxAQAAAA==.Ramrod:BAAALgAECgIJAwAAAA==.Ramstank:BAAALgAECgEJAQAAAA==.Randomizwe:BAABLgAECn8uAAIBAAkJtB5EIwB4AgABAAkJtB5EIwB4AgAAAA==.Raspet:BAAALgADCgIJAgAAAA==.Rattles:BAAALgADCgcJCwAAAA==.Raynu:BAAALgAECgEJAwAAAA==.Raín:BAAALgAECggJDwAAAA==.',
Re='Reisa:BAAALgAECgEJAQAAAA==.Relearning:BAABLgAECn8zAAIKAAkJYBBaCQArAQAKAAkJYBBaCQArAQAAAA==.Relyn:BAABLgAECn8UAAIQAAgJWQchigAMAQAQAAgJWQchigAMAQAAAA==.Resurgencê:BAABLgAECn8/AAICAAkJnCJHAAAcAwACAAkJnCJHAAAcAwAAAA==.Retalltheway:BAAALgADCgEJAQAAAA==.',
Ri='Riggler:BAAALgAECgcJBwAAAA==.Riordan:BAABLgAECn8mAAMBAAgJ6BQykgBOAQABAAcJChQykgBOAQACAAQJ9xPgJQDnAAAAAA==.',
Ro='Rohz:BAAALgADCgIJAgABLgAECgcJIAAQAKYeAA==.Rojeton:BAAALgADCgUJBwAAAA==.Rosenth:BAAALgADCggJEwAAAA==.Rotandroll:BAAALgAECgcJDwAAAA==.Rothema:BAABLgAECn8pAAMjAAkJjwz+BgAZAQAjAAkJjwz+BgAZAQASAAgJQQRLGwBkAAAAAA==.Routh:BAAALgAECgEJAQAAAA==.',
Rw='Rwlmaster:BAABLgAECn9CAAITAAkJhxuuDwAQAgATAAkJhxuuDwAQAgAAAA==.',
Ry='Rynzia:BAACLgAFFH8ZAAMoAAQJMhkiBAAtAQAcAAQJMhmcJwAuAQAoAAQJMxMiBAAtAQAuAAQKf0cABCgACQngIa0BANECACgACQktH60BANECABwACQnJIGEMAJUCAB0ABwnnErsSAJ0BAAAA.',
Sa='Sadabacus:BAAALgAECgEJAgAAAA==.Sagetempest:BAAALgADCgEJAQAAAA==.Sagittarian:BAAALgADCgUJBwAAAA==.Sandwiches:BAABLgAECn8WAAIOAAgJrRiOAwC9AQAOAAgJrRiOAwC9AQAAAA==.Santose:BAAALgAECgIJAgAAAA==.Sarya:BAAALgAECgQJBAABLgAECgkJAwADAAAAAA==.',
Sc='Scalyt:BAAALgADCgYJBgAAAA==.Scerra:BAABLgAECn8mAAIUAAkJExBnTgDXAQAUAAkJExBnTgDXAQAAAA==.Schmerz:BAAALgADCgUJBQAAAA==.Scridders:BAAALgAECgMJAwAAAA==.Scridderz:BAAALgAECgMJBgAAAA==.',
Se='Sendia:BAAALgADCgQJBAABLgAECgIJAgADAAAAAA==.Sephiros:BAAALgADCgIJAgAAAA==.Seru:BAABLgAECn8WAAIXAAgJfh+vBAAVAgAXAAgJfh+vBAAVAgAAAA==.Seta:BAABLgAECn8bAAIQAAgJ3xNeQwDmAQAQAAgJ3xNeQwDmAQAAAA==.Seviran:BAAALgADCgIJAwAAAA==.',
Sh='Shakeyjams:BAAALgADCgYJBgABLgAFFAIJBgAUAL4cAA==.Shamantha:BAAALgADCgEJAQAAAA==.Shamarha:BAABLgAECn8dAAISAAgJaBoKMwDmAQASAAgJaBoKMwDmAQAAAA==.Shaolin:BAAALgAECgQJBAAAAA==.Sharriavolf:BAABLgAECn9FAAQKAAkJsCOLQADbAQAKAAcJ1SGLQADbAQAJAAQJ+CMLIABSAQAIAAEJAAB7IwBkAAAAAA==.Shato:BAAALgAECgYJCQAAAA==.Shellee:BAAALgAECgMJAwAAAA==.Sheoth:BAAALgADCgQJBAAAAA==.Shiori:BAAALgAECgcJEAAAAA==.Shortmedic:BAAALgAECgQJBAAAAA==.Shotzys:BAAALgAECgYJEgAAAA==.Shrieve:BAAALgAECgMJAwAAAA==.Shurg:BAAALgAECgQJBAAAAA==.',
Si='Sicarius:BAAALgADCgcJCgABLgAECgMJBAADAAAAAA==.Siggismund:BAABLgAECn8rAAIBAAkJKguWeAB9AQABAAkJKguWeAB9AQAAAA==.Simichaelton:BAACLgAFFH8PAAIMAAYJxBAxYQAfAQAMAAYJxBAxYQAfAQAuAAQKfx0AAgwACQkYG1ZJAP8BAAwACQkYG1ZJAP8BAAAA.Sinpal:BAABLgAFFH8LAAIBAAQJYBPtMwCjAAABAAQJYBPtMwCjAAAAAA==.Sinthea:BAAALgAECgkJAgAAAA==.Sioce:BAAALgADCgkJKwAAAA==.',
Sk='Skrobifu:BAAALgADCgQJAwAAAA==.',
Sl='Slickacitic:BAAALgAECgYJBwABLgAECgcJHwASAAwLAA==.Slimselect:BAAALgADCgMJAwAAAA==.Slimt:BAAALgADCgMJAwAAAA==.Sloppyshids:BAAALgAECgcJCAAAAA==.Slur:BAAALgADCgIJAgABLgAECgIJBgADAAAAAA==.',
Sm='Smackurazz:BAAALgAECgMJAwAAAA==.Smorroy:BAAALgADCgYJBgAAAA==.',
So='Softbakedhoj:BAABLgAECn8eAAIBAAgJ/BxdSQAGAgABAAgJ/BxdSQAGAgAAAA==.Sophrosyne:BAABLgAECn8vAAIXAAkJjRvfLwAdAgAXAAkJjRvfLwAdAgAAAA==.Souless:BAAALgAECgYJBgAAAA==.',
Sp='Spankie:BAAALgAECgcJDgAAAA==.Sparkness:BAAALgAECgMJAwAAAA==.Spartaaxd:BAABLgAECn8yAAIgAAkJkRCrAwAIAQAgAAkJkRCrAwAIAQAAAA==.Spookems:BAAALgAECgIJAgABLgAFFAMJAwADAAAAAA==.Spycy:BAABLgAECn8UAAIMAAkJ3BA3hQBtAQAMAAkJ3BA3hQBtAQAAAA==.',
St='Stabbard:BAAALgAECgEJAQAAAA==.Stagerrind:BAAALgAECgUJEQAAAA==.Starfall:BAAALgAECgkJAgAAAA==.Steiner:BAABLgAECn8qAAMGAAkJOwzhNAB+AQAGAAkJOwzhNAB+AQABAAEJ9QcBtgEnAAAAAA==.Steps:BAAALgAECgQJBAAAAA==.Stinkyfrog:BAACLgAFFH8GAAIBAAMJxQzshgClAAABAAMJxQzshgClAAAuAAQKfyUAAgEACQlQIuALAAYDAAEACQlQIuALAAYDAAAA.Stovetop:BAAALgAECgEJAQABLgAECgUJBwADAAAAAA==.Stubmcbean:BAAALgAECgQJBAABLgAECgkJRAAfADcJAA==.Stunted:BAAALgAECgMJAwAAAA==.',
Su='Sugarfrost:BAABLgAECn8mAAIMAAkJOgs5pAA0AQAMAAkJOgs5pAA0AQAAAA==.Sugarseer:BAAALgAECgQJBAABLgAECgkJJgAMADoLAA==.Suka:BAABLgAECn8ZAAINAAYJsQenCwCkAAANAAYJsQenCwCkAAAAAA==.Surok:BAAALgAECgYJDwAAAA==.',
Sw='Sweetleaf:BAAALgAECgUJCAAAAA==.Swiftleaf:BAAALgAECgcJDAAAAA==.',
Sy='Sylentcurse:BAABLgAECn8sAAIIAAkJlg0NAgBdAQAIAAkJlg0NAgBdAQAAAA==.Sylentstorm:BAABLgAECn8cAAMSAAgJYwPKgwDXAAASAAgJYwPKgwDXAAAjAAEJAAAHyQAAAAABLgAECgkJLAAIAJYNAA==.Syleta:BAABLgAECn9LAAQZAAkJKiCaBADjAgAZAAkJ3h+aBADjAgAXAAcJwxwNMADwAQAaAAYJCRNpRABEAQABLgAECgIJAgADAAAAAA==.',
Ta='Tabraxis:BAAALgAECgEJAQAAAA==.Tagalorc:BAABLgAECn8fAAMlAAkJPRVFAwD2AQAlAAkJPRVFAwD2AQAMAAEJ8QGigQEcAAAAAA==.Takamaki:BAAALgAECgEJAwAAAA==.Tanksbacon:BAABLgAECn8oAAMBAAkJgBnKMAA9AgABAAkJgBnKMAA9AgACAAQJtxKSLwCWAAAAAA==.Taylith:BAAALgAECgYJEgAAAA==.',
Te='Teana:BAACLgAFFH8IAAIgAAMJ2weNCwC2AAAgAAMJ2weNCwC2AAAuAAQKfyIAAiAACAnkD5MQAG0BACAACAnkD5MQAG0BAAAA.Teannev:BAAALgADCgYJBgAAAA==.Tempestas:BAAALgAECgEJAQAAAA==.Teraax:BAAALgADCgEJAQAAAA==.',
Th='Tharos:BAAALgAECgUJCgAAAA==.Thebrewco:BAAALgADCgMJAwABLgAFFAUJEwAOANYSAA==.Thechadd:BAABLgAFFH8HAAIjAAcJaAPhNwCvAAAjAAcJaAPhNwCvAAAAAA==.Thelegendáry:BAACLgAFFH8QAAISAAQJlxR3IACwAAASAAQJlxR3IACwAAAuAAQKfxoAAhIABgmWF0FKAFkBABIABgmWF0FKAFkBAAAA.Thetool:BAAALgAECgMJBAAAAA==.Thevileone:BAAALgAECggJCAABLgAFFAQJGQATAJgdAA==.Thraine:BAAALgAECgYJCwAAAA==.',
Ti='Tinyshadowz:BAAALgAECgEJAQAAAA==.Tione:BAABLgAECn87AAMNAAkJQhz+EgA9AgANAAgJMh3+EgA9AgAOAAkJFQuXVAA+AQAAAA==.Tireck:BAAALgADCggJCQAAAA==.',
To='Toriee:BAAALgAECgkJCQAAAA==.Tormented:BAAALgAECgMJAwAAAA==.Totembish:BAABLgAECn8gAAIjAAkJZAnaPABCAQAjAAkJZAnaPABCAQAAAA==.Totocatt:BAAALgAFFAkJAgAAAA==.',
Tr='Treebear:BAAALgADCgcJDQAAAA==.Tremor:BAAALgAECgIJAwAAAA==.Trisstan:BAABLgAECn8vAAMMAAkJYgtlkgBTAQAMAAkJYgtlkgBTAQApAAMJawEvDQBVAAAAAA==.Trucknly:BAAALgADCgMJAwAAAA==.',
Tu='Tundarian:BAAALgAECggJDwAAAA==.Tundie:BAAALgAFFAEJAQAAAA==.',
Tw='Twigz:BAAALgADCgcJBgAAAA==.',
Ty='Tyronicals:BAABLgAECn8iAAMMAAkJshvsOwAqAgAMAAkJkBjsOwAqAgAlAAUJHyAJBgDAAQAAAA==.Tyster:BAACLgAFFH8XAAIBAAUJyRQsGAAVAQABAAUJyRQsGAAVAQAuAAQKfyMAAwEACQl0FSBEAPoBAAEACQnGFCBEAPoBAAIAAQkbFgNKAEEAAAAA.',
['Tø']='Tørmëntëd:BAAALgAECgMJBAAAAA==.',
Ug='Ugotdusted:BAAALgADCgYJBgAAAA==.',
Uk='Ukyo:BAAALgADCgUJBgAAAA==.',
Ul='Ullidon:BAAALgAECgIJAgAAAA==.',
Um='Umbrã:BAAALgADCgEJAQAAAA==.',
Un='Unavoidably:BAAALgADCgIJAgAAAA==.Undol:BAAALgADCggJGwABLgAECgkJRAAfADcJAA==.',
Ux='Uxe:BAAALgAFFAEJAQABLgAECgkJJAAnAFkaAA==.',
Uz='Uzu:BAABLgAECn8kAAMnAAkJWRqeJQCBAQAnAAkJWRqeJQCBAQAVAAEJyhLTjQBDAAAAAA==.',
Va='Valios:BAAALgADCgcJBwAAAA==.Valorr:BAAALgAECgQJBAAAAA==.Vamp:BAABLgAECn8YAAISAAgJxxbxLwDIAQASAAgJxxbxLwDIAQAAAA==.Vandaldor:BAAALgAECgYJEQAAAA==.Vandrana:BAAALgAECgUJCQAAAA==.Vasalrius:BAAALgADCgIJAgAAAA==.Vasilli:BAAALgADCgYJDwAAAA==.',
Ve='Vedrix:BAAALgAECgcJBgAAAA==.Vellora:BAAALgADCgUJBQAAAA==.Veloth:BAACLgAFFH8dAAIMAAQJYhkEUAA+AQAMAAQJYhkEUAA+AQAuAAQKfzMAAgwACQnwIh4iAJUCAAwACQnwIh4iAJUCAAAA.Vexnyx:BAAALgADCgcJCAAAAA==.',
Vh='Vhitahni:BAAALgAECgMJAwAAAA==.',
Vi='Viggle:BAAALgAECgQJBAABLgAECgkJPwACAJwiAA==.Vireaux:BAAALgADCgEJAQAAAA==.Viviro:BAAALgADCgcJDQAAAA==.',
Vl='Vll:BAABLgAECn8nAAMXAAkJtRsKKQA6AgAXAAkJtRsKKQA6AgAZAAIJewTpKgBVAAABLgAECggJIgALAO4iAA==.',
Vo='Voodoomike:BAAALgAECgIJAgAAAA==.',
Vy='Vynlorin:BAAALgAECgYJBgABLgAECgkJMgABAFQgAA==.',
Wa='Wanawa:BAAALgAECgMJAwABLgAECgkJIgAYABwVAA==.Wanghaf:BAAALgAECgYJDQAAAA==.Warhorne:BAAALgAECgEJAQABLgAECgkJIgAYABwVAA==.Warloque:BAAALgAECgMJAwAAAA==.Warthog:BAAALgADCgkJGQAAAA==.Waterbender:BAABLgAECn8ZAAISAAkJRRqPGQB+AgASAAkJRRqPGQB+AgAAAA==.',
We='Weechuup:BAAALgAECgMJBAAAAA==.Weleindon:BAAALgADCgMJAwAAAA==.',
Wi='Wifeotusk:BAAALgAECgkJEAAAAA==.Wiggle:BAAALgADCgMJAwAAAA==.Willmar:BAABLgAECn8hAAIBAAgJ2hY3UQDVAQABAAgJ2hY3UQDVAQAAAA==.Wilshaman:BAAALgAECggJEAAAAA==.Window:BAAALgADCgUJBQABLgAECgcJIAAQAKYeAA==.',
Wm='Wmdplague:BAAALgADCgYJBgAAAA==.',
Wo='Wolf:BAABLgAECn8wAAIEAAkJPhndAQDdAQAEAAkJPhndAQDdAQAAAA==.Wolfton:BAAALgAECgMJAwAAAA==.Woodtique:BAAALgAECgQJCgAAAA==.',
Wr='Wrekkit:BAAALgAECgkJEQAAAA==.',
Wy='Wylian:BAAALgAECgIJAgAAAA==.',
Xa='Xaeri:BAAALgADCgMJBAAAAA==.Xameris:BAAALgADCgEJAQAAAA==.Xandercruise:BAABLgAECn8UAAMXAAgJIhvAHQBTAgAXAAgJIhvAHQBTAgAaAAMJrAJgdABtAAAAAA==.',
Xe='Xelgoth:BAAALgADCgcJBgAAAA==.Xelphie:BAAALgADCgUJBQAAAA==.',
Xi='Xiia:BAAALgAECgIJAgABLgAECgQJBQADAAAAAA==.',
Xu='Xuchilbara:BAABLgAECn8eAAIYAAgJuRojCwALAgAYAAgJuRojCwALAgAAAA==.',
Xy='Xyro:BAAALgAECgUJBQABLgAFFAMJBQAUAAwRAA==.',
Ya='Yamato:BAAALgAECgcJDQAAAA==.',
Za='Zaledron:BAABLgAECn8jAAIUAAgJcCCDBwCEAQAUAAgJcCCDBwCEAQAAAA==.Zapnasty:BAAALgADCgcJBgAAAA==.',
Ze='Zenno:BAABLgAECn8sAAMfAAkJBxOwEACoAQAfAAkJBxOwEACoAQASAAMJVgiBtgBeAAAAAA==.Zevorcia:BAAALgAECgMJAwAAAA==.',
Zh='Zhades:BAACLgAFFH8lAAMUAAUJXB0yIAA4AQAUAAUJXB0yIAA4AQAgAAMJ/RXRCADgAAAuAAQKf0YAAxQACQmiJY8HADkDABQACQmiJY8HADkDACAACAlQIf0DAJcCAAAA.Zhandaria:BAAALgAECgQJBwAAAA==.Zhandraia:BAAALgADCgUJBQAAAA==.Zhort:BAAALgAECgIJAwAAAA==.Zhulodok:BAAALgADCgMJAwAAAA==.',
Zi='Zioki:BAAALgAECgMJBAAAAA==.',
Zm='Zmrfister:BAAALgAECgYJBgABLgAFFAUJJQAUAFwdAA==.',
Zo='Zodgul:BAAALgAECgQJBAAAAA==.Zomby:BAABLgAFFH8IAAIUAAMJXA6KpwDMAAAUAAMJXA6KpwDMAAABLgAFFAYJDwAMAMQQAA==.',
Zp='Zpersephone:BAABLgAECn8cAAIKAAcJDxMjaQBqAQAKAAcJDxMjaQBqAQABLgAFFAUJJQAUAFwdAA==.',
Zr='Zrii:BAAALgAECggJDQAAAA==.',
Zu='Zultan:BAACLgAFFH8RAAIKAAQJawfsaADzAAAKAAQJawfsaADzAAAuAAQKf0MAAwoACQnKGQsgAGUCAAoACQnKGQsgAGUCAAkAAglmBBtIABkAAAAA.Zurrik:BAACLgAFFH8LAAMNAAQJTwYRMQC+AAANAAQJEgQRMQC+AAAEAAMJYQZ/KgBxAAAuAAQKfz4AAw0ACQm0EuggAMIBAA0ACQnwEeggAMIBAAQAAgn+E0NNAHcAAAAA.',
Zy='Zynofhealth:BAAALgADCgUJAwAAAA==.',
['Çõ']='Çõîñflïp:BAAALgADCgcJHAAAAA==.',
['Ðr']='Ðream:BAACLgAFFH8GAAInAAMJqBTYEgDjAAAnAAMJqBTYEgDjAAAuAAQKfycAAycACAmEHzsJAPUCACcACAmEHzsJAPUCABUAAwkjGQ2ZADYAAAAA.',
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
