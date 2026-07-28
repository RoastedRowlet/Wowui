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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Paladin-Protection','Druid-Guardian','Priest-Discipline','Paladin-Holy','Warrior-Fury','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','DemonHunter-Havoc','Mage-Frost','Druid-Balance','Druid-Restoration','DemonHunter-Vengeance','DemonHunter-Devourer','Monk-Mistweaver','Shaman-Restoration','DeathKnight-Blood','DeathKnight-Frost','DeathKnight-Unholy','Monk-Windwalker','Warrior-Protection','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Feral','Hunter-Survival','Rogue-Subtlety','Evoker-Augmentation','Evoker-Preservation','Shaman-Enhancement','Warrior-Arms','Priest-Shadow','Priest-Holy','Shaman-Elemental','Rogue-Outlaw','Mage-Arcane','Rogue-Assassination','Monk-Brewmaster','Evoker-Devastation','Mage-Fire',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=46,date='2026-07-28',data={Ab='Abberleigh:BAAALgAFFAMJAwAAAA==.',
Ad='Adonya:BAAALgADCgIJAQAAAA==.',
Ae='Aelgagar:BAAALgAECgYJEAAAAA==.Aelirina:BAAALgAECgMJAwAAAA==.Aerostotle:BAAALgAECggJCQAAAA==.',
Af='Afkyouheâl:BAAALgAECgYJBgAAAA==.',
Ah='Ahamay:BAAALgADCgEJAgAAAA==.',
Ai='Ailde:BAAALgADCgkJDgAAAA==.',
Ak='Akikah:BAAALgAFFAEJAQAAAA==.Akshhan:BAABLgAFFH8IAAIBAAUJlxBKSQAaAQABAAUJlxBKSQAaAQAAAA==.',
Al='Alaepo:BAAALgADCgYJBgABLgAECgMJBAACAAAAAA==.Alania:BAAALgADCgYJCAAAAA==.Alaraa:BAABLgAECn8mAAMDAAgJLB4WCQBCAgADAAgJLB4WCQBCAgABAAIJ4xVQMwF7AAABLgAECgIJAgACAAAAAA==.Alarlia:BAABLgAECn8jAAIEAAgJvgtkMQDlAAAEAAgJvgtkMQDlAAAAAA==.Alathor:BAAALgAECgEJAQAAAA==.Algonq:BAABLgAECn8gAAIFAAYJZQRbEAC1AAAFAAYJZQRbEAC1AAABLgAECgkJRgAGAO8GAA==.Alliesofevil:BAABLgAECn8nAAIHAAkJbBU+JgDGAQAHAAkJbBU+JgDGAQAAAA==.Allsar:BAABLgAECn8aAAIEAAkJnB07BgCeAgAEAAkJnB07BgCeAgAAAA==.Alsar:BAAALgAECgQJBwABLgAECgkJGgAEAJwdAA==.Alssar:BAAALgAECgYJCwAAAA==.Alstar:BAAALgAECgEJAgAAAA==.',
Am='Amaraa:BAAALgAECgMJAwAAAA==.Amathus:BAACLgAFFH8SAAQIAAUJhQ5VBQDTAAAIAAQJxRBVBQDTAAAJAAQJywRzEACwAAAKAAMJ1gT5iwCtAAAuAAQKf3gABAkACQmwGwcEAEgCAAkACQkaGgcEAEgCAAgABwlHGmQBAOABAAoACQnFFGtGAMcBAAAA.Amaunet:BAAALgADCgUJBQAAAA==.Amentia:BAAALgAECgQJBAAAAA==.',
An='Anahilis:BAAALgADCgcJCAAAAA==.Andarial:BAABLgAECn8bAAILAAkJDQ/lJwA9AQALAAkJDQ/lJwA9AQAAAA==.Andella:BAAALgAECgIJAgAAAA==.Andreth:BAABLgAECn8aAAIMAAkJBQugEQA6AQAMAAkJBQugEQA6AQAAAA==.Angellus:BAAALgAECgYJBgAAAA==.Anoxaroll:BAAALgADCgQJBAAAAA==.Anoxyn:BAAALgAECgcJCQAAAA==.Anthe:BAABLgAECn8fAAMNAAcJBw+6CAAXAQANAAcJBw+6CAAXAQAOAAIJwgW9HgA0AAAAAA==.Anzul:BAABLgAECn8yAAMBAAkJVCCUJAByAgABAAkJQh+UJAByAgADAAUJxB0TGgBIAQAAAA==.',
Ar='Araestirra:BAABLgAECn80AAMJAAcJmBKeAwA0AQAJAAYJzBSeAwA0AQAKAAcJBgc4qwDsAAAAAA==.Arcanmaggy:BAAALgADCgkJHgABLgAFFAYJHwAKAPUFAA==.Ardahh:BAAALgADCgQJBAAAAA==.Arnold:BAABLgAECn8YAAMPAAgJ6hSYCwCjAQAPAAgJ6hSYCwCjAQAQAAEJagPLOgEbAAABLgAECgkJGgAEAJwdAA==.Arntdorn:BAAALgADCgEJAQAAAA==.Arroes:BAABLgAECn8ZAAIRAAgJGB/qFgBiAgARAAgJGB/qFgBiAgAAAA==.',
As='Asahna:BAAALgAECgQJBAAAAA==.',
At='Atisse:BAAALgAECgEJAQAAAA==.Atlas:BAAALgAECggJCgABLgAECgkJGgAEAJwdAA==.',
Au='Aurrell:BAAALgADCgcJBwAAAA==.',
Av='Avoid:BAAALgAECgMJAwAAAA==.',
Ay='Ayroona:BAABLgAECn8pAAISAAkJOgpVTgB4AQASAAkJOgpVTgB4AQAAAA==.',
Az='Azhol:BAAALgAECgQJBAAAAA==.',
Ba='Bacontotem:BAAALgADCgMJBQAAAA==.Baelhal:BAACLgAFFH8cAAMTAAQJmB08FQBEAQATAAQJmB08FQBEAQAUAAIJLAXlFABpAAAuAAQKfzQAAhMACQmaHUIOACYCABMACQmaHUIOACYCAAAA.Balka:BAAALgADCgYJCAAAAA==.Barbaydos:BAAALgADCggJCQAAAA==.Barenjager:BAAALgAECgEJAQAAAA==.Basement:BAABLgAECn8gAAIQAAcJph4mMQABAgAQAAcJph4mMQABAgAAAA==.',
Be='Beastnite:BAAALgAECgIJAgABLgAECgkJGwAVANkLAA==.Bellaburger:BAABLgAFFH8IAAIWAAQJsgYfIgDOAAAWAAQJsgYfIgDOAAAAAA==.Bellissidan:BAAALgAECgEJAwAAAA==.Benedin:BAAALgAECgYJEQABLgAECgkJSQAIAM4gAA==.',
Bi='Bigpapapete:BAAALgAECgYJAwAAAA==.Bigtex:BAABLgAECn86AAMHAAkJ+gy+CwD3AAAHAAkJbwu+CwD3AAAXAAQJmA6gCACuAAAAAA==.Biped:BAABLgAECn8zAAIIAAkJPhNbCADkAQAIAAkJPhNbCADkAQAAAA==.Birill:BAAALgAECgEJAgAAAA==.Bishul:BAAALgAECggJCQAAAA==.',
Bl='Blackdeath:BAACLgAFFH8FAAIVAAIJSgmG6wB+AAAVAAIJSgmG6wB+AAAuAAQKfzMAAhUACQkjHcELAGABABUACQkjHcELAGABAAAA.',
Bo='Bombarian:BAAALgAECgUJCwAAAA==.Bone:BAAALgAECgEJAQAAAA==.Boomstique:BAABLgAECn9VAAMYAAkJ8h0qAwCrAgAYAAkJ8h0qAwCrAgAZAAEJbwkFDQAoAAAAAA==.Boondocka:BAACLgAFFH8GAAIYAAQJZQ0qIwAQAQAYAAQJZQ0qIwAQAQAuAAQKfzgAAhgACQkrHIUcAHoCABgACQkrHIUcAHoCAAAA.',
Br='Brewco:BAACLgAFFH8UAAMOAAYJLxDaLQD9AAAOAAYJLxDaLQD9AAAaAAEJzRvBDgBMAAAuAAQKfzkABA4ACQkEHKYUAJACAA4ACQkEHKYUAJACABoABgnDG1YSAJYBAAQABQl6Dw49ALIAAAAA.Brewer:BAAALgAECgEJAQAAAA==.Brickmebtch:BAAALgAFFAIJAgAAAA==.Brissennissa:BAAALgAECgEJAQAAAA==.Bruda:BAAALgAECgIJAwAAAA==.Brutalís:BAABLgAECn8pAAIYAAkJOhICPwDmAQAYAAkJOhICPwDmAQABLgAECgkJLQAIANsNAA==.',
Bt='Btrain:BAABLgAECn8iAAMDAAcJ/AmaMQCfAAABAAcJmwZa9ADFAAADAAUJgAyaMQCfAAAAAA==.',
['Bó']='Bóunty:BAABLgAECn8bAAQbAAcJwx8lHwCjAQAbAAcJrh0lHwCjAQAYAAQJNx5HXgBNAQAZAAEJPgJtmAAeAAAAAA==.',
Ca='Camaryn:BAAALgADCgIJAgAAAA==.Canadia:BAAALgAECgQJBgAAAA==.Caritta:BAAALgAECgQJBAAAAA==.Catdaddan:BAAALgADCgYJBgAAAA==.Cattnip:BAAALgAECgEJAQAAAA==.Cavisch:BAABLgAECn9JAAMIAAkJziAcAQD/AgAIAAkJziAcAQD/AgAKAAkJWBi7OwDsAQAAAA==.',
Ce='Cedric:BAAALgAECgIJAgABLgAECgcJCQACAAAAAA==.Celiia:BAAALgAECgUJCAABLgAECgIJAgACAAAAAA==.Celtique:BAAALgAECgIJAgAAAA==.Cenobité:BAABLgAECn87AAMUAAkJyRooAQBUAgAUAAkJyRooAQBUAgAVAAEJhBHISQAzAAAAAA==.Cerr:BAAALgAECgMJBAAAAA==.',
Ch='Chamber:BAAALgAECgYJCAABLgAECgcJIAAQAKYeAA==.Chantilly:BAAALgADCgYJDwAAAA==.Chaosmaster:BAAALgAECgMJAwAAAA==.Chardee:BAABLgAFFH8HAAIcAAMJlBUmDQAVAQAcAAMJlBUmDQAVAQAAAA==.Charmeleon:BAABLgAECn8UAAMdAAgJCRJ1QQAjAQAdAAgJCRJ1QQAjAQAeAAIJfAwbNABWAAAAAA==.Charmin:BAAALgADCgUJBQAAAA==.Chicka:BAAALgAECgIJAgABLgAECgYJCQACAAAAAA==.Chiff:BAAALgADCgUJAwAAAA==.Chilledog:BAAALgADCgQJBAAAAA==.Chip:BAAALgAECgMJBgAAAA==.Churg:BAAALgAECgQJBAAAAA==.',
Ci='Ciari:BAAALgAECgIJAgAAAA==.Cirax:BAABLgAECn82AAIYAAgJkxuFBQA3AgAYAAgJkxuFBQA3AgAAAA==.Cirin:BAAALgADCgEJAQAAAA==.Citruscoolin:BAAALgAECgEJAQAAAA==.',
Cl='Cleetess:BAAALgAECgEJAQAAAA==.Clenton:BAACLgAFFH8GAAIDAAMJ4QECDgBEAAADAAMJ4QECDgBEAAAuAAQKf3kAAwMACQk3DVAFACMBAAMACQnWC1AFACMBAAEACAkJCEWvACABAAAA.Clipper:BAAALgADCgYJBgAAAA==.',
Co='Cobrakai:BAAALgAECgIJAgAAAA==.Cowboyup:BAAALgADCgYJBgAAAA==.',
Cr='Crichton:BAACLgAFFH8UAAIQAAQJ9Rl5PgAtAQAQAAQJ9Rl5PgAtAQAuAAQKfzIAAhAACQm0IYIMAOECABAACQm0IYIMAOECAAAA.Cronnan:BAAALgAECgUJBQAAAA==.Crowford:BAABLgAECn85AAIYAAkJNBStEgA3AQAYAAkJNBStEgA3AQAAAA==.Crups:BAAALgADCgQJBAAAAA==.',
Cy='Cyris:BAAALgAECgYJCwABLgAECgkJSQAfAF8KAA==.',
['Cá']='Cástle:BAAALgAECgEJAQABLgAECgcJIAAQAKYeAA==.',
Da='Daemonfaust:BAAALgAECgYJDwAAAA==.Daevahna:BAAALgADCgYJBgAAAA==.Dahtty:BAAALgAECgYJBwAAAA==.Dak:BAABLgAECn8bAAIBAAgJjRhqTwDzAQABAAgJjRhqTwDzAQABLgAFFAMJBgAVAM0UAA==.Dakdeekay:BAACLgAFFH8GAAIVAAMJzRQDOgDnAAAVAAMJzRQDOgDnAAAuAAQKfyUAAhUACQlbF7UwADwCABUACQlbF7UwADwCAAAA.Daksclaw:BAAALgAFFAIJAgABLgAFFAMJBgAVAM0UAA==.Daksmash:BAAALgAECgUJCAABLgAFFAMJBgAVAM0UAA==.Dakstab:BAAALgADCgkJCQAAAA==.Dalsar:BAABLgAECn8UAAMEAAgJywfxNwDHAAAEAAgJywfxNwDHAAAOAAQJKAlnEQCBAAAAAA==.Darkbrew:BAAALgADCgYJCAABLgAECgkJPwADAPohAA==.Darkfes:BAAALgAECgEJAQAAAA==.Darkmiza:BAACLgAFFH8fAAIKAAYJ9QVnbgDlAAAKAAYJ9QVnbgDlAAAuAAQKfzsAAwoACAl1EVJlAHMBAAoACAl1EVJlAHMBAAkAAglDC0lYAGYAAAAA.Darthbluto:BAAALgAECgUJDQABLgAECgYJDwACAAAAAA==.Dasham:BAAALgAECgQJBAAAAA==.Daymann:BAABLgAECn8iAAIBAAkJHRa8SQDpAQABAAkJHRa8SQDpAQAAAA==.',
De='Deadazz:BAAALgADCgYJCgAAAA==.Deadmangalad:BAABLgAECn8/AAMUAAkJ+g5bAwBRAQAUAAkJxg5bAwBRAQATAAUJzQ1mCgCrAAAAAA==.Deathnotes:BAAALgADCgEJAQAAAA==.Deathquina:BAAALgAECgMJAwAAAA==.Deathtickle:BAAALgAECgcJAwAAAA==.Deedees:BAABLgAECn8eAAINAAgJ5QZ8QwD/AAANAAgJ5QZ8QwD/AAAAAA==.Demonbo:BAACLgAFFH8GAAIQAAIJvQ+VPgBsAAAQAAIJvQ+VPgBsAAAuAAQKfxoAAhAACAmIFBRkAF8BABAACAmIFBRkAF8BAAAA.Demondrink:BAAALgAECgQJBgAAAA==.Demonhandler:BAAALgADCggJDwAAAA==.Demonikk:BAAALgAECgYJCgAAAA==.Deo:BAACLgAFFH8YAAMHAAQJGiDkEQB4AQAHAAQJGiDkEQB4AQAgAAMJMBTPKADKAAAuAAQKfz8AAwcACQkmJAAEACYDAAcACQkmJAAEACYDACAAAgmSDeVjAFoAAAAA.Depression:BAAALgADCgUJBQAAAA==.Derpixion:BAABLgAECn8tAAMYAAgJYhlFJwAcAgAYAAgJYhlFJwAcAgAbAAUJYQtJPgDSAAAAAA==.Dessirius:BAAALgAECgEJAQAAAA==.Dethphalanax:BAAALgAECgEJAQAAAA==.',
Di='Digbie:BAAALgADCgYJBwAAAA==.Digs:BAAALgADCgMJAwAAAA==.Dirtnåp:BAABLgAECn8WAAIBAAYJFBJ5FwADAQABAAYJFBJ5FwADAQAAAA==.Diskbänk:BAAALgAECgUJBwAAAA==.',
Dk='Dkho:BAACLgAFFH8FAAIMAAMJ7gNqkwCuAAAMAAMJ7gNqkwCuAAAuAAQKfxUAAgwACAnCDbV/AHgBAAwACAnCDbV/AHgBAAAA.',
Dr='Drago:BAAALgAECgEJBAAAAA==.Dragontoast:BAAALgAECgkJEwAAAA==.Dral:BAEALgADCgkJKAAAAA==.Draygun:BAAALgAECgcJBwABLgAFFAQJGAAHABogAA==.Drphilyobody:BAABLgAECn8cAAIVAAcJCQhMsgARAQAVAAcJCQhMsgARAQAAAA==.Drui:BAABLgAECn8dAAINAAgJsQ4dNgBkAQANAAgJsQ4dNgBkAQAAAA==.Druidïan:BAAALgAECgQJBQAAAA==.',
Du='Duelittle:BAABLgAECn8qAAIhAAcJmQ14DADYAAAhAAcJmQ14DADYAAAAAA==.',
Dy='Dynwor:BAAALgAECgEJAgAAAA==.',
['Dé']='Dérailed:BAAALgAECgUJEgAAAA==.',
['Dî']='Dîz:BAAALgADCgEJAQAAAA==.',
Ea='Easme:BAABLgAECn8zAAMbAAkJBA8JBAA4AQAbAAkJBA8JBAA4AQAZAAUJRANPYgC3AAAAAA==.Eatmyfrontal:BAABLgAECn88AAIMAAkJvxoAPwAgAgAMAAkJvxoAPwAgAgABLgAFFAIJAgACAAAAAA==.',
Eb='Ebbola:BAAALgADCgcJDgAAAA==.Ebon:BAAALgAECgQJBgABLgAECgkJDQACAAAAAA==.',
Eh='Ehsinat:BAAALgADCgYJBgAAAA==.',
El='Elaraa:BAAALgAECgYJBwAAAA==.Elaric:BAAALgAECgcJCQAAAA==.Elger:BAAALgADCgEJAgAAAA==.Elvi:BAAALgAECgEJAQAAAA==.',
Em='Emory:BAAALgADCgEJAQAAAA==.',
En='Engi:BAAALgAECgcJDgAAAA==.',
Ep='Epikrate:BAABLgAECn8fAAMKAAgJURl8QADbAQAKAAcJIRl8QADbAQAJAAMJ4hiqSACUAAAAAA==.',
Es='Escaper:BAABLgAECn84AAIUAAkJcxLOCwC7AQAUAAkJcxLOCwC7AQAAAA==.',
Ex='Extrema:BAABLgAECn8WAAILAAkJGRvkAgDxAQALAAkJGRvkAgDxAQAAAA==.',
Ez='Ezsdruid:BAAALgAECgkJCQAAAA==.',
Fa='Faesha:BAAALgAECgEJAQAAAA==.Fallenash:BAAALgADCgMJAwABLgAFFAQJFgAMAGsfAA==.Fallenembers:BAACLgAFFH8WAAIMAAQJax/0QwBhAQAMAAQJax/0QwBhAQAuAAQKfzsAAgwACQlJJb8GAEsDAAwACQlJJb8GAEsDAAAA.Famine:BAABLgAECn8dAAMVAAgJ0AWlvAACAQAVAAgJwwSlvAACAQAUAAUJzAf7DADfAAAAAA==.Farquaadtwo:BAAALgAECgIJAgAAAA==.',
Fe='Fearofthdark:BAAALgADCgEJAQAAAA==.',
Ff='Fflar:BAAALgADCgUJBQABLgAECgkJAwACAAAAAA==.',
Fh='Fhait:BAABLgAECn87AAMFAAgJ1xYqAwARAgAFAAcJKhkqAwARAgAhAAgJNw5uBwBDAQABLgAECgkJUwAWAK4SAA==.',
Fi='Firsttimepvp:BAACLgAFFH8HAAIcAAIJJg3xNQCJAAAcAAIJJg3xNQCJAAAuAAQKfx4AAhwACQnaE6kUAPwBABwACQnaE6kUAPwBAAAA.',
Fl='Flow:BAAALgADCgYJBgAAAA==.',
Fo='Foxfu:BAAALgAECgYJBgAAAA==.',
Fr='Frenchtoast:BAAALgAECgIJAgAAAA==.Frostyflaker:BAAALgAECgUJDAAAAA==.',
Ga='Gaiã:BAAALgADCgEJAgAAAA==.Galadan:BAABLgAECn8mAAMEAAkJGQxhCwC3AAAEAAYJcA1hCwC3AAAaAAgJ/wYzCgB3AAABLgAECgkJPwAUAPoOAA==.Garrekton:BAAALgAECgEJAgABLgAECgkJSQAIAM4gAA==.Gaskelmarg:BAAALgAECgUJDwAAAA==.',
Ge='Gellane:BAAALgAECgQJBQAAAA==.',
Gh='Ghosty:BAABLgAECn8hAAQFAAkJIRWWHwDRAQAFAAkJsRGWHwDRAQAiAAcJpAuKTgD+AAAhAAEJcAEanAAXAAAAAA==.Ghuun:BAAALgADCgEJAgABLgAFFAMJCAARAAoMAA==.',
Gi='Gigaweed:BAABLgAFFH8IAAIRAAMJCgx/RQCOAAARAAMJCgx/RQCOAAAAAA==.',
Go='Goblinlayer:BAAALgAECgYJEwAAAA==.Goldtusk:BAABLgAECn8iAAIaAAkJHBVbDgDQAQAaAAkJHBVbDgDQAQAAAA==.Gooey:BAAALgADCggJDgAAAA==.Gostann:BAABLgAECn8mAAIKAAkJlRclJwBAAgAKAAkJlRclJwBAAgAAAA==.Goy:BAAALgAECgUJBQAAAA==.',
Gr='Grayparser:BAAALgADCgYJCQAAAA==.Grimsly:BAAALgAECgEJAQAAAA==.Grundler:BAAALgAFFAEJAQAAAA==.Gryphone:BAAALgADCgkJEQAAAA==.',
Gu='Gurinendo:BAAALgAECgEJAgAAAA==.Gustwin:BAAALgAECgQJBgAAAA==.',
['Gà']='Gàins:BAAALgAECgQJBAABLgAECgkJPwADAPohAA==.',
Ha='Hakmud:BAAALgADCgYJCwAAAA==.Halsin:BAAALgADCgMJAwABLgAECggJIQAjAD0aAA==.Hamshammy:BAAALgAECgEJAQAAAA==.',
He='Heftydin:BAAALgAECgMJCQAAAA==.Heftymists:BAAALgAECgUJBQAAAA==.Heftystomp:BAAALgADCgUJBQAAAA==.Heftyvoid:BAAALgADCgEJAQAAAA==.Hela:BAAALgADCgcJBwAAAA==.Hercyderc:BAAALgAECgEJAQABLgAFFAIJBQAQADYgAA==.Hettokal:BAAALgAECgcJCQAAAA==.Heximal:BAAALgAFFAMJAwABLgAFFAQJBgAYAGUNAA==.Heyitsjimbo:BAAALgADCgUJCQAAAA==.',
Ho='Holierhtanu:BAAALgADCgQJBwAAAA==.Holyhellion:BAABLgAECn8dAAIQAAkJchEFRQC4AQAQAAkJchEFRQC4AQAAAA==.Hondojoe:BAACLgAFFH8YAAIiAAQJvx5lDwBbAQAiAAQJvx5lDwBbAQAuAAQKfz4ABCIACQnuIEoLAJsCACIACQnuIEoLAJsCACEAAwnOHsAJAAoBAAUAAgnYBv1uAE0AAAAA.Honeydrake:BAAALgAECgYJCAAAAA==.Hopewell:BAABLgAECn9GAAIGAAkJ7wZpCgDnAAAGAAkJ7wZpCgDnAAAAAA==.',
Hu='Huginn:BAAALgADCgEJAQAAAA==.Hugnsnuggle:BAABLgAECn9DAAIPAAkJcg0mAgB0AQAPAAkJcg0mAgB0AQABLgAECgkJUwAWAK4SAA==.Huhu:BAABLgAECn8ZAAIHAAkJrxRhKwCnAQAHAAkJrxRhKwCnAQAAAA==.Huma:BAAALgAECgYJEAABLgAFFAQJCgAYAAAOAA==.Hundreg:BAAALgADCgYJBQAAAA==.',
['Hô']='Hôlydiver:BAAALgAECgIJAwAAAA==.',
Ib='Ibn:BAABLgAECn8tAAIgAAkJpQs1HwBkAQAgAAkJpQs1HwBkAQAAAA==.',
Ic='Icyhot:BAAALgAECgYJDwAAAA==.',
Id='Ideal:BAAALgADCgYJDAAAAA==.',
Il='Illaris:BAAALgADCgIJAgAAAA==.',
In='Infiniity:BAAALgAECgMJCQAAAA==.Inksmear:BAAALgAECgEJAgAAAA==.',
Ir='Irielle:BAABLgAECn8UAAMOAAYJsxBBCgD5AAAOAAYJsxBBCgD5AAANAAEJAAC+KQAAAAAAAA==.',
Is='Ishanllin:BAAALgAECgIJAgAAAA==.',
Iv='Ivarurngamet:BAABLgAECn8iAAIQAAkJyRfaLgALAgAQAAkJyRfaLgALAgAAAA==.Ivylyn:BAAALgAECgkJDgAAAA==.',
Ix='Ixiyá:BAABLgAECn89AAMSAAkJNCNtBABxAwASAAkJNCNtBABxAwAjAAEJzghXrgAqAAAAAA==.Ixií:BAAALgAECgEJAwAAAA==.Ixì:BAABLgAECn8XAAIOAAcJ1x31IQA4AgAOAAcJ1x31IQA4AgAAAA==.',
Ja='Jakbequick:BAAALgAECgEJAQAAAA==.Jakeyprogue:BAAALgAFFAIJAwABLgAFFAIJBgAVAL4cAA==.Jakota:BAAALgADCgkJFAAAAA==.Jakskeleton:BAABLgAECn8fAAITAAgJ2xoYEAAKAgATAAgJ2xoYEAAKAgAAAA==.Jarobus:BAAALgAECgYJDgAAAA==.Jay:BAAALgADCgEJAQAAAA==.Jaynamir:BAAALgAECgYJEwAAAA==.Jayp:BAAALgAECgMJAwAAAA==.',
Jb='Jbernn:BAAALgAECgEJAQAAAA==.',
Je='Jeamica:BAAALgAECgQJCAAAAA==.',
Jo='Joemacho:BAAALgAECgcJEwABLgAFFAQJGAAiAL8eAA==.Joerollin:BAACLgAFFH8GAAIRAAMJMBk/HADaAAARAAMJMBk/HADaAAAuAAQKfxgAAhEACQlDHj4BAAwDABEACQlDHj4BAAwDAAEuAAUUBAkYACIAvx4A.Joshtee:BAAALgAECgMJBQAAAA==.Joslyn:BAAALgAECgQJBQAAAA==.Jourdan:BAAALgADCgcJDQAAAA==.',
Ju='Judax:BAACLgAFFH8KAAIjAAMJaQ8FNwCyAAAjAAMJaQ8FNwCyAAAuAAQKfz0AAiMACQm0GyUTAFUCACMACQm0GyUTAFUCAAAA.Justagirl:BAABLgAECn9TAAIWAAkJrhKIAgDbAQAWAAkJrhKIAgDbAQAAAA==.Justiceboyd:BAAALgADCgMJAwAAAA==.Juti:BAABLgAECn8YAAIjAAYJZAMUFgByAAAjAAYJZAMUFgByAAAAAA==.',
Jy='Jymion:BAAALgADCgEJAQAAAA==.',
['Jú']='Júun:BAAALgADCgEJAQAAAA==.',
Ka='Kadooka:BAACLgAFFH8KAAIYAAMJtBN5KgDvAAAYAAMJtBN5KgDvAAAuAAQKfygAAhgACAmkGToLAJ0BABgACAmkGToLAJ0BAAAA.Kahlyn:BAAALgAECggJDwAAAA==.Kajax:BAABLgAECn8qAAIcAAgJISMwCAANAwAcAAgJISMwCAANAwAAAA==.Kaldaran:BAABLgAECn8YAAQUAAkJjBsUBQAIAQATAAkJ1BnKGwB+AQAUAAMJ3x0UBQAIAQAVAAIJtQTrUwFOAAAAAA==.Kallan:BAAALgAECgYJEAABLgAECgkJPwADAPohAA==.Kalleigh:BAAALgADCgQJBAABLgAECgkJSQAfAF8KAA==.Karen:BAAALgAECgQJBAAAAA==.Karinn:BAAALgADCgEJAQAAAA==.Karne:BAAALgADCgYJBgAAAA==.Katira:BAAALgAECgQJCQAAAA==.Kazarath:BAAALgADCgUJBQAAAA==.',
Ke='Keeganw:BAABLgAECn8fAAMTAAYJThuSJgAfAQATAAYJThuSJgAfAQAVAAEJKRINRwA5AAAAAA==.Keelay:BAACLgAFFH8GAAIGAAIJgiRZEQDTAAAGAAIJgiRZEQDTAAAuAAQKf2MAAgYACQkQIo0AACoDAAYACQkQIo0AACoDAAAA.',
Kh='Khyla:BAAALgAECgEJAQAAAA==.',
Ki='Killua:BAAALgADCgYJBgABLgADCgcJCwACAAAAAA==.Kimiko:BAAALgAECgcJEAAAAA==.',
Kl='Klaw:BAAALgAECgQJBAABLgAECggJKgAcACEjAA==.',
Ko='Koffcmorbius:BAABLgAECn8UAAIYAAYJmAn9HwDKAAAYAAYJmAn9HwDKAAAAAA==.Koriban:BAABLgAECn8lAAIMAAkJaA69aQCoAQAMAAkJaA69aQCoAQAAAA==.Korreban:BAAALgAECgYJBgABLgAECgkJJQAMAGgOAA==.',
Kr='Kra:BAAALgAECgEJAgABLgAFFAMJCAARAAoMAA==.Kraken:BAACLgAFFH8GAAIJAAMJ1hKrDQDIAAAJAAMJ1hKrDQDIAAAuAAQKfysAAgkACQlzIvIAAAUDAAkACQlzIvIAAAUDAAEuAAUUAwkIABEACgwA.Krim:BAAALgADCgYJBgAAAA==.',
Ku='Kubb:BAABLgAECn9JAAIfAAkJXwrxAwA+AQAfAAkJXwrxAwA+AQAAAA==.Kunst:BAAALgADCgEJAQAAAA==.',
Kv='Kvitravn:BAAALgAECgMJAwABLgAECgMJCAACAAAAAA==.',
Kw='Kweh:BAACLgAFFH8fAAIaAAYJlh+sAQDcAQAaAAYJlh+sAQDcAQAuAAQKfy0AAxoACQk6IxoFAMACABoACQk6IxoFAMACAA0ABQkbDqZGAPEAAAAA.',
Ky='Kytrina:BAAALgAECgEJAQAAAA==.',
['Kê']='Kêlsen:BAAALgAECgUJBwAAAA==.',
La='Lachupacabra:BAAALgAECgEJAQAAAA==.Larrissa:BAABLgAECn80AAMIAAkJMQk3AwA9AQAIAAkJMQk3AwA9AQAJAAEJggPhewAlAAAAAA==.Larry:BAABLgAFFH8UAAIQAAcJBhNiPgAtAQAQAAcJBhNiPgAtAQAAAA==.Lauris:BAAALgADCgMJAwAAAA==.Laurlynn:BAABLgAECn8cAAMSAAgJ4AOYGACsAAASAAgJ4AOYGACsAAAjAAYJHQSMFQB4AAAAAA==.Lavina:BAAALgADCgUJBQAAAA==.',
Le='Lemixalot:BAAALgADCgEJAQAAAA==.Lenwe:BAAALgAECgYJEQABLgAECgcJNQAiAD0RAA==.Lettuceprey:BAABLgAECn9NAAIiAAkJsw+7BgBOAQAiAAkJsw+7BgBOAQAAAA==.',
Li='Lierise:BAABLgAECn8ZAAQVAAkJmRtCBgDsAQAVAAcJIxxCBgDsAQAUAAUJhhZMAwBVAQATAAUJMxCVPACfAAAAAA==.Lies:BAAALgADCgkJCQAAAA==.Lightsnipe:BAAALgAECgQJBAAAAA==.Lilkelp:BAAALgAECgYJCQAAAA==.Lilspazz:BAAALgADCgMJAwAAAA==.Lithiri:BAAALgAECgUJDwABLgAFFAIJBQAVAOEaAA==.',
Lo='Lockatute:BAAALgAECgkJEgAAAA==.Lockdeath:BAAALgAECgQJCQAAAA==.Locknessy:BAAALgAECgEJAQAAAA==.Loric:BAAALgADCgkJCQAAAA==.Loxia:BAABLgAECn8XAAIJAAkJxA1yEwAWAQAJAAkJxA1yEwAWAQAAAA==.',
Lu='Lucille:BAACLgAFFH8FAAIMAAEJfAZBbgA+AAAMAAEJfAZBbgA+AAAuAAQKfyEAAgwACAn1EyUMAIQBAAwACAn1EyUMAIQBAAAA.Luckett:BAAALgADCgEJAQAAAA==.Lucrotia:BAAALgADCgQJBAAAAA==.Luukmosh:BAAALgAECgUJCQAAAA==.',
Ma='Maavarra:BAABLgAECn8/AAMaAAkJsCJbAAAOAwAaAAkJsCJbAAAOAwAOAAQJLRTiCwDVAAAAAA==.Madilyons:BAAALgADCgIJAgAAAA==.Madischa:BAAALgAECgcJEgAAAA==.Madshaggy:BAABLgAECn8VAAIDAAkJZBAgAwCTAQADAAkJZBAgAwCTAQAAAA==.Magicdance:BAACLgAFFH8JAAIjAAQJxQJnOACtAAAjAAQJxQJnOACtAAAuAAQKfzsAAxIACQmHEUZLAIMBABIACQmHEUZLAIMBACMACQmeCiEPAL0AAAAA.Magolthel:BAAALgADCgYJCQAAAA==.Maimgame:BAABLgAECn8WAAIaAAgJchK/CwACAgAaAAgJchK/CwACAgAAAA==.Majicbob:BAABLgAECn8hAAIjAAgJPRoSHgDxAQAjAAgJPRoSHgDxAQAAAA==.Maki:BAABLgAECn8UAAMkAAkJ/BTeEgDcAAAcAAkJ/BRXLwCJAQAkAAUJxRDeEgDcAAAAAA==.Mansion:BAAALgADCgQJBgABLgAECgcJIAAQAKYeAA==.Marilune:BAAALgADCggJCQAAAA==.Marn:BAAALgADCgQJBAAAAA==.Marthran:BAAALgADCgIJAgAAAA==.Maxlin:BAAALgAECgIJAwAAAA==.',
Mc='Mctowlie:BAAALgAECgYJCAAAAA==.',
Me='Mehänemäntä:BAABLgAECn8WAAIYAAkJaguuEQBBAQAYAAkJaguuEQBBAQAAAA==.Meldo:BAAALgADCggJDQAAAA==.Mellinessa:BAABLgAECn8aAAMUAAcJqBXJEwBAAQAVAAYJJRKQlABXAQAUAAUJWBXJEwBAAQAAAA==.Mena:BAAALgADCgUJBgAAAA==.Merixa:BAAALgADCgEJAQAAAA==.',
Mf='Mfdkidney:BAAALgAECgIJAgAAAA==.',
Mi='Midou:BAAALgAECgMJAwABLgAFFAQJCQAjAMUCAA==.Minthraxis:BAAALgADCgEJAQAAAA==.Misaun:BAAALgAECgEJAgABLgAECgMJBAACAAAAAA==.Misericorde:BAACLgAFFH8QAAIWAAQJUyTRCACNAQAWAAQJUyTRCACNAQAuAAQKfzwAAhYACQkYJqUBAF0DABYACQkYJqUBAF0DAAAA.Misstreater:BAABLgAECn8oAAMMAAkJSgp7EQA8AQAMAAkJ3wl7EQA8AQAlAAcJyQYkCgDpAAAAAA==.',
Mo='Momentomori:BAABLgAECn8gAAIKAAkJvghkbwBcAQAKAAkJvghkbwBcAQAAAA==.Monbow:BAAALgAECgMJBwABLgAFFAIJBgAQAL0PAA==.Monocerotis:BAAALgAECgQJBAAAAA==.Morishima:BAACLgAFFH8dAAIcAAQJ6xmoFgBYAQAcAAQJ6xmoFgBYAQAuAAQKf08AAxwACQlkJPcCACIDABwACQlkJPcCACIDACYAAQkJFtklAD0AAAAA.Morthis:BAABLgAECn84AAMZAAkJPhMiAQDbAQAZAAkJPhMiAQDbAQAbAAMJWgM5WABMAAAAAA==.',
Mt='Mtpoccy:BAAALgADCgYJBgAAAA==.',
Mu='Muffington:BAAALgAECgEJAQAAAA==.Multipàss:BAAALgADCgcJCgAAAA==.',
My='Mydarling:BAAALgAFFAIJAwAAAA==.Mymoon:BAAALgAECgIJAgAAAA==.Myris:BAACLgAFFH8IAAIVAAMJ7Q9vYACOAAAVAAMJ7Q9vYACOAAAuAAQKfzwAAhUACQmlH4wFAAoCABUACQmlH4wFAAoCAAAA.',
Na='Narcan:BAAALgAECgUJDQAAAA==.Naturalchi:BAABLgAECn8wAAMWAAkJByWbAgBCAwAWAAkJiiSbAgBCAwAnAAgJ8x5yDABuAgAAAA==.',
Nb='Nbi:BAAALgAECgEJAgAAAA==.',
Ne='Nefilion:BAABLgAFFH8GAAIVAAIJ7wsI6QB/AAAVAAIJ7wsI6QB/AAAAAA==.Nemas:BAABLgAECn8hAAIDAAgJrxnuDgDVAQADAAgJrxnuDgDVAQAAAA==.Neophalanax:BAAALgADCgMJAwAAAA==.Netanyahu:BAAALgADCgUJBQAAAA==.Neverleft:BAAALgAECgUJCAAAAA==.Nezin:BAABLgAECn8tAAQdAAkJkhb6AgCiAQAdAAkJUBX6AgCiAQAoAAYJJRNDDwAXAQAeAAIJuQ2jQABlAAAAAA==.',
Ni='Nightrun:BAAALgADCgcJCwAAAA==.Nightrunnêr:BAAALgAECgUJCwABLgAECgkJPwADAPohAA==.Nineadin:BAACLgAFFH8VAAMBAAQJnwsQWAAAAQABAAQJnwsQWAAAAQAGAAQJLhf1DwDmAAAuAAQKfycAAwYACQmYHU0TAHgCAAYACQmYHU0TAHgCAAEAAgkjHZ0IAa4AAAAA.Nineshots:BAAALgAFFAMJBAABLgAFFAQJFQABAJ8LAA==.Ninetoads:BAAALgAECgcJDQABLgAFFAQJFQABAJ8LAA==.Niraz:BAAALgAECgEJAQABLgAECgIJAgACAAAAAA==.Nirvanas:BAABLgAECn8dAAIaAAgJ/A10HQAeAQAaAAgJ/A10HQAeAQAAAA==.Niyoko:BAAALgADCgcJBwAAAA==.',
No='Nomik:BAABLgAECn81AAMiAAcJPRHQCwDGAAAiAAcJPRHQCwDGAAAhAAYJRAh4FQBxAAAAAA==.Nonah:BAAALgADCgEJAgAAAA==.North:BAAALgAECggJCAAAAA==.',
Nr='Nrglmrgl:BAAALgAECgEJAQAAAA==.',
Nu='Nuke:BAABLgAECn8VAAIYAAQJvBkVGwDrAAAYAAQJvBkVGwDrAAAAAA==.Nullspace:BAABLgAECn8qAAMiAAkJXhq+FAAvAgAiAAkJXhq+FAAvAgAhAAMJAQxRFAB9AAAAAA==.Nunskee:BAAALgAECgQJBAAAAA==.',
['Ní']='Níght:BAABLgAECn86AAMEAAgJqhhYFQCqAQAEAAgJKRdYFQCqAQAaAAEJ3hdnEQBDAAAAAA==.',
Oa='Oaken:BAAALgADCgkJCgAAAA==.',
Ob='Oboro:BAAALgAECgEJAQAAAA==.',
Oc='Occultivated:BAAALgAECgQJBwAAAA==.',
Od='Oddtotem:BAAALgADCgMJAwAAAA==.',
Oh='Ohhk:BAAALgAECgMJAwAAAA==.',
Om='Ommu:BAAALgADCgMJAwABLgAECgMJCAACAAAAAA==.Ommû:BAAALgAECgMJCAAAAA==.',
Op='Op:BAAALgAECgIJAgABLgAFFAMJCAARAAoMAA==.',
Or='Orillar:BAAALgADCgEJAQAAAA==.',
Pa='Pakeydk:BAABLgAFFH8GAAIVAAIJvhxWxgCfAAAVAAIJvhxWxgCfAAAAAA==.Palacia:BAAALgAECggJEQAAAA==.Pancakedealr:BAAALgAECgUJEAAAAA==.Pancakeeater:BAAALgAECgUJCgAAAA==.Pappabeary:BAAALgADCgMJAwAAAA==.',
Pe='Peaches:BAAALgAECgEJAQAAAA==.Peerow:BAAALgADCgMJAwAAAA==.Permelia:BAAALgADCgkJDwAAAA==.Petrichorica:BAABLgAECn8tAAIjAAkJxwO5EACqAAAjAAkJxwO5EACqAAAAAA==.Peí:BAAALgAECgEJAQAAAA==.',
Ph='Phatjake:BAAALgADCgYJBgAAAA==.',
Pi='Ping:BAABLgAFFH8GAAIRAAYJ3RQ/CwDQAQARAAYJ3RQ/CwDQAQAAAA==.Pintobeans:BAABLgAECn8XAAIYAAkJlQVJdwBRAQAYAAkJlQVJdwBRAQAAAA==.',
Pl='Plutonix:BAAALgAECgMJBQAAAA==.',
Pr='Preachêr:BAAALgAECgQJCQABLgAECgkJPwADAPohAA==.Priestorz:BAAALgADCgcJDQAAAA==.Prohteus:BAAALgAECgEJAQABLgAECgMJBQACAAAAAA==.',
Pu='Puuhceew:BAACLgAFFH8JAAIiAAMJnBDvDwCpAAAiAAMJnBDvDwCpAAAuAAQKfyIAAiIACQn6DbU2ACUBACIACQn6DbU2ACUBAAAA.',
Qu='Quan:BAEALgADCgcJCQABLgADCgkJKAACAAAAAA==.Quelaag:BAAALgADCgQJBAAAAA==.Quenthel:BAAALgAECgkJAwAAAA==.Quiescent:BAABLgAECn8pAAIQAAgJdRr2KQAiAgAQAAgJdRr2KQAiAgAAAA==.Quina:BAAALgAECgQJBwAAAA==.',
Ra='Ragingtides:BAAALgADCgEJAQAAAA==.Rainera:BAABLgAECn8zAAMIAAkJJSW8AQDWAgAIAAkJJSW8AQDWAgAKAAEJAxH1OgE1AAABLgAFFAgJJAAPAB4kAA==.Ramanas:BAABLgAECn8bAAMhAAkJ0BPOLwBgAQAhAAgJVxTOLwBgAQAFAAYJnBGILQAxAQAAAA==.Ramrod:BAAALgAECgMJBAAAAA==.Ramstank:BAAALgAECgEJAgAAAA==.Randomizwe:BAABLgAECn8uAAIBAAkJtB5EIwB4AgABAAkJtB5EIwB4AgAAAA==.Raspet:BAAALgADCgIJAgAAAA==.Rattles:BAAALgADCgcJCwAAAA==.Raynu:BAAALgAECgEJAwAAAA==.Raín:BAAALgAECggJDwAAAA==.',
Re='Redgicide:BAAALgAECgYJBgABLgAFFAQJBgAYAGUNAA==.Reisa:BAAALgAECgEJAQAAAA==.Relearning:BAABLgAECn8zAAIKAAkJYBDkCwAqAQAKAAkJYBDkCwAqAQAAAA==.Relyn:BAABLgAECn8UAAIQAAgJWQchigAMAQAQAAgJWQchigAMAQAAAA==.Resurgencê:BAABLgAECn8/AAIDAAkJ+iGAAAD+AgADAAkJ+iGAAAD+AgAAAA==.Retalltheway:BAAALgADCgEJAQAAAA==.',
Ri='Riggler:BAAALgAECgcJBwAAAA==.Riordan:BAABLgAECn8mAAMBAAgJ6BQykgBOAQABAAcJChQykgBOAQADAAQJ9xPgJQDnAAAAAA==.',
Ro='Rohz:BAAALgADCgIJAgABLgAECgcJIAAQAKYeAA==.Rojeton:BAAALgADCgUJBwAAAA==.Rosenth:BAAALgADCggJEwAAAA==.Rotandroll:BAAALgAECgcJDwAAAA==.Rothema:BAABLgAECn8vAAMjAAkJMwwbBwBQAQAjAAkJMwwbBwBQAQASAAgJQQRxJQBbAAAAAA==.Routh:BAAALgAECgEJAQAAAA==.',
Rw='Rwlmaster:BAABLgAECn9CAAITAAkJhxuuDwAQAgATAAkJhxuuDwAQAgAAAA==.',
Ry='Rynzia:BAACLgAFFH8ZAAMoAAQJMhkiBAAtAQAdAAQJMhmcJwAuAQAoAAQJMxMiBAAtAQAuAAQKf0cABCgACQngIa0BANECACgACQktH60BANECAB0ACQnJIGEMAJUCAB4ABwnnErsSAJ0BAAAA.',
Sa='Sadabacus:BAAALgAECgEJAgAAAA==.Sagetempest:BAAALgADCgEJAQAAAA==.Sagittarian:BAAALgADCgUJBwAAAA==.Sandwiches:BAABLgAECn8aAAIOAAkJ/RmZAgBIAgAOAAkJ/RmZAgBIAgAAAA==.Santose:BAAALgAECgIJAgAAAA==.Sarya:BAAALgAECgQJBAABLgAECgkJAwACAAAAAA==.',
Sc='Scalyt:BAAALgADCgYJBgAAAA==.Scerra:BAABLgAECn8mAAIVAAkJExBnTgDXAQAVAAkJExBnTgDXAQAAAA==.Schmerz:BAAALgADCgUJBQAAAA==.Scridders:BAAALgAECgUJBwAAAA==.Scridderz:BAAALgAECgMJBgAAAA==.',
Se='Sendia:BAAALgADCgQJBAABLgAECgIJAgACAAAAAA==.Sephiros:BAAALgADCgIJAgAAAA==.Seru:BAABLgAECn8fAAIYAAkJbCJeAQAjAwAYAAkJbCJeAQAjAwAAAA==.Seta:BAABLgAECn8bAAIQAAgJ3xNeQwDmAQAQAAgJ3xNeQwDmAQAAAA==.Seviran:BAAALgADCgIJAwAAAA==.',
Sh='Shakeyjams:BAAALgADCgYJBgABLgAFFAIJBgAVAL4cAA==.Shamantha:BAAALgADCgEJAQAAAA==.Shamarha:BAABLgAECn8dAAISAAgJaBoKMwDmAQASAAgJaBoKMwDmAQAAAA==.Shaolin:BAAALgAECgQJBAAAAA==.Sharriavolf:BAABLgAECn9FAAQKAAkJsCOLQADbAQAKAAcJ1SGLQADbAQAJAAQJ+CMLIABSAQAIAAEJAAB7IwBkAAAAAA==.Shato:BAAALgAECgYJCQAAAA==.Shellee:BAAALgAECgMJBgAAAA==.Sheoth:BAAALgADCgQJBAAAAA==.Shiori:BAAALgAECgcJEAAAAA==.Shortmedic:BAAALgAECgQJBAAAAA==.Shotzys:BAAALgAECgYJEgAAAA==.Shrieve:BAAALgAECgMJAwAAAA==.Shurg:BAAALgAECgQJBAAAAA==.',
Si='Sicarius:BAAALgADCgcJCgABLgAECgMJBAACAAAAAA==.Siggismund:BAABLgAECn8rAAIBAAkJKguWeAB9AQABAAkJKguWeAB9AQAAAA==.Simichaelton:BAACLgAFFH8QAAIMAAYJ7xExYQAfAQAMAAYJ7xExYQAfAQAuAAQKfx0AAgwACQkYG1ZJAP8BAAwACQkYG1ZJAP8BAAAA.Sinpal:BAABLgAFFH8MAAIBAAQJYBOnJwDmAAABAAQJYBOnJwDmAAAAAA==.Sinthea:BAAALgAECgkJAgAAAA==.Sioce:BAAALgADCgkJKwAAAA==.',
Sk='Skrobifu:BAAALgADCgQJAwAAAA==.',
Sl='Slickacitic:BAAALgAECgYJBwABLgAECgcJHwASAAwLAA==.Slimselect:BAAALgADCgMJAwAAAA==.Slimt:BAAALgADCgMJAwAAAA==.Sloppyshids:BAAALgAECgcJCAAAAA==.Slur:BAAALgADCgIJAgABLgAECgUJBgACAAAAAA==.',
Sm='Smackurazz:BAAALgAECgMJAwAAAA==.Smorroy:BAAALgADCgYJBgAAAA==.',
So='Softbakedhoj:BAABLgAECn8eAAIBAAgJ/BxdSQAGAgABAAgJ/BxdSQAGAgAAAA==.Sophrosyne:BAABLgAECn8vAAIYAAkJjRvfLwAdAgAYAAkJjRvfLwAdAgAAAA==.Souless:BAAALgAECgYJBgAAAA==.',
Sp='Spankie:BAAALgAECgcJDgAAAA==.Sparkness:BAAALgAECgMJAwAAAA==.Spartaaxd:BAABLgAECn8yAAIUAAkJkRDwBAANAQAUAAkJkRDwBAANAQAAAA==.Spookems:BAAALgAECgIJAgABLgAFFAMJAwACAAAAAA==.Spycy:BAABLgAECn8UAAIMAAkJ3BA3hQBtAQAMAAkJ3BA3hQBtAQAAAA==.',
Sq='Squirrellock:BAAALgAECgYJBgAAAA==.',
St='Stabbard:BAAALgAECgEJAQAAAA==.Stagerrind:BAAALgAECgUJEQAAAA==.Starfall:BAAALgAECgkJCwAAAA==.Steiner:BAABLgAECn8qAAMGAAkJOwzhNAB+AQAGAAkJOwzhNAB+AQABAAEJ9QcBtgEnAAAAAA==.Steps:BAAALgAECgQJBAAAAA==.Stinkyfrog:BAACLgAFFH8GAAIBAAMJxQzshgClAAABAAMJxQzshgClAAAuAAQKfyUAAgEACQlQIuALAAYDAAEACQlQIuALAAYDAAAA.Stovetop:BAAALgAECgEJAQABLgAECgUJBwACAAAAAA==.Stubmcbean:BAAALgAECgUJDQABLgAECgkJSQAfAF8KAA==.Stunted:BAAALgAECgMJAwAAAA==.',
Su='Sugarfrost:BAABLgAECn8mAAIMAAkJOgs5pAA0AQAMAAkJOgs5pAA0AQAAAA==.Sugarseer:BAAALgAECgQJBAABLgAECgkJJgAMADoLAA==.Suka:BAABLgAECn8dAAINAAYJZwkVEACeAAANAAYJZwkVEACeAAAAAA==.Surok:BAAALgAECgYJDwAAAA==.',
Sw='Sweetleaf:BAAALgAECgUJCAAAAA==.Swiftleaf:BAAALgAECgcJDAAAAA==.',
Sy='Sylentcurse:BAABLgAECn8tAAIIAAkJ2w2UAgBnAQAIAAkJ2w2UAgBnAQAAAA==.Sylentstorm:BAABLgAECn8cAAMSAAgJYwPKgwDXAAASAAgJYwPKgwDXAAAjAAEJAAAHyQAAAAABLgAECgkJLQAIANsNAA==.Syleta:BAABLgAECn9LAAQbAAkJKiCaBADjAgAbAAkJ3h+aBADjAgAYAAcJwxwNMADwAQAZAAYJCRNpRABEAQABLgAECgIJAgACAAAAAA==.Sylvarus:BAAALgADCgEJAQAAAA==.',
Ta='Tabraxis:BAAALgAECgEJAQAAAA==.Tagalorc:BAABLgAECn8fAAMlAAkJPRVFAwD2AQAlAAkJPRVFAwD2AQAMAAEJ8QGigQEcAAAAAA==.Takamaki:BAAALgAECgEJAwAAAA==.Talto:BAAALgADCgYJBgAAAA==.Tamara:BAAALgAECgMJAwAAAA==.Tanksbacon:BAABLgAECn8oAAMBAAkJgBnKMAA9AgABAAkJgBnKMAA9AgADAAQJtxKSLwCWAAAAAA==.Taylith:BAABLgAECn8WAAIBAAYJTQsAMQB0AAABAAYJTQsAMQB0AAAAAA==.',
Te='Teana:BAACLgAFFH8MAAIUAAQJqgv/CAAAAQAUAAQJqgv/CAAAAQAuAAQKfyIAAhQACAnkD5MQAG0BABQACAnkD5MQAG0BAAAA.Teannev:BAAALgADCgYJBgAAAA==.Tempestas:BAAALgAECgEJAQAAAA==.Teraax:BAAALgADCgEJAQAAAA==.',
Th='Tharos:BAAALgAECgUJCgAAAA==.Thebrewco:BAAALgADCgMJAwABLgAFFAYJFAAOAC8QAA==.Thechadd:BAABLgAFFH8IAAIjAAcJaAPhNwCvAAAjAAcJaAPhNwCvAAAAAA==.Thelegendáry:BAACLgAFFH8QAAISAAQJlxQ/PADyAAASAAQJlxQ/PADyAAAuAAQKfxoAAhIABgmWF0FKAFkBABIABgmWF0FKAFkBAAAA.Thetool:BAAALgAECgMJBAAAAA==.Thevileone:BAAALgAECggJCAABLgAFFAQJHAATAJgdAA==.Thraine:BAAALgAECgYJCwAAAA==.',
Ti='Tinyshadowz:BAAALgAECgEJAQAAAA==.Tione:BAABLgAECn87AAMNAAkJQhz+EgA9AgANAAgJMh3+EgA9AgAOAAkJFQuXVAA+AQAAAA==.Tireck:BAAALgADCggJCQAAAA==.Titanthanos:BAAALgADCgMJAwAAAA==.',
To='Toadvoker:BAAALgAECgYJBgABLgAFFAQJFQABAJ8LAA==.Toriee:BAAALgAECgkJCQAAAA==.Tormented:BAAALgAECgMJAwAAAA==.Totembish:BAABLgAECn8hAAIjAAkJ6AnaPABCAQAjAAkJ6AnaPABCAQAAAA==.Totocatt:BAAALgAFFAkJAwAAAA==.',
Tr='Treebear:BAAALgADCgcJDQAAAA==.Tremor:BAAALgAECgIJAwAAAA==.Trickyeasy:BAAALgAECgEJAQAAAA==.Trisstan:BAABLgAECn8zAAMMAAkJmgzOFAAdAQAMAAkJmgzOFAAdAQApAAMJawEvDQBVAAAAAA==.Trucknly:BAAALgADCgMJAwAAAA==.',
Tu='Tundarian:BAAALgAECggJDwAAAA==.Tundie:BAAALgAFFAEJAQAAAA==.',
Tw='Twigz:BAAALgADCgcJBgAAAA==.',
Ty='Tyronicals:BAABLgAECn8iAAMMAAkJshvsOwAqAgAMAAkJkBjsOwAqAgAlAAUJHyAJBgDAAQAAAA==.Tyster:BAACLgAFFH8XAAIBAAUJyRTuHgALAQABAAUJyRTuHgALAQAuAAQKfyMAAwEACQl0FSBEAPoBAAEACQnGFCBEAPoBAAMAAQkbFgNKAEEAAAAA.',
['Tø']='Tørmëntëd:BAAALgAECgMJBAAAAA==.',
Ug='Ugotdusted:BAAALgADCgYJBgAAAA==.',
Uk='Ukyo:BAAALgAECgEJAQAAAA==.',
Ul='Ullidon:BAAALgAECgIJAgAAAA==.',
Um='Umbrã:BAAALgADCgEJAQAAAA==.',
Un='Unavoidably:BAAALgADCgIJAgAAAA==.Undol:BAAALgADCggJGwABLgAECgkJSQAfAF8KAA==.',
Ux='Uxe:BAAALgAFFAEJAQABLgAECgkJJAAnAFkaAA==.',
Uz='Uzu:BAABLgAECn8kAAMnAAkJWRqeJQCBAQAnAAkJWRqeJQCBAQAWAAEJyhLTjQBDAAAAAA==.',
Va='Valios:BAAALgADCgcJBwAAAA==.Valorr:BAAALgAECgQJBAAAAA==.Vamp:BAABLgAECn8YAAISAAgJxxbxLwDIAQASAAgJxxbxLwDIAQAAAA==.Vandaldor:BAAALgAECgYJEQAAAA==.Vandrana:BAAALgAECgUJCQAAAA==.Vasalrius:BAAALgADCgIJAgAAAA==.Vasilli:BAAALgADCgYJDwAAAA==.',
Ve='Vedrix:BAAALgAECgcJBgAAAA==.Vellora:BAAALgADCgUJBQAAAA==.Veloth:BAACLgAFFH8iAAIMAAUJcR0IIgBPAQAMAAUJcR0IIgBPAQAuAAQKfzMAAgwACQnwIh4iAJUCAAwACQnwIh4iAJUCAAAA.Vexnyx:BAAALgADCgcJCAAAAA==.',
Vh='Vhitahni:BAAALgAECgMJAwAAAA==.',
Vi='Viggle:BAAALgAECgQJBAABLgAECgkJPwADAPohAA==.Viho:BAAALgAECgEJAQAAAA==.Vireaux:BAAALgADCgEJAQAAAA==.Viviro:BAAALgADCgcJDQAAAA==.',
Vl='Vll:BAABLgAECn8nAAMYAAkJtRsKKQA6AgAYAAkJtRsKKQA6AgAbAAIJewTpKgBVAAABLgAECggJIgALAO4iAA==.',
Vo='Voodoomike:BAAALgAECgIJAgAAAA==.',
Vy='Vynlorin:BAAALgAECgYJBgABLgAECgkJMgABAFQgAA==.',
Wa='Wanawa:BAAALgAECgMJAwABLgAECgkJIgAaABwVAA==.Wanghaf:BAAALgAECgYJDQAAAA==.Warhorne:BAAALgAECgEJAQABLgAECgkJIgAaABwVAA==.Warloque:BAAALgAECgMJBQAAAA==.Warthog:BAAALgADCgkJGQAAAA==.Waterbender:BAABLgAECn8ZAAISAAkJRRqPGQB+AgASAAkJRRqPGQB+AgAAAA==.',
We='Weechuup:BAAALgAECgUJCAAAAA==.Weleindon:BAAALgADCgMJAwAAAA==.',
Wi='Wifeotusk:BAAALgAECgkJEAAAAA==.Wiggle:BAAALgADCgMJAwAAAA==.Willmar:BAABLgAECn8hAAIBAAgJ2hY3UQDVAQABAAgJ2hY3UQDVAQAAAA==.Wilshaman:BAABLgAECn8UAAISAAYJYwP2GwCPAAASAAYJYwP2GwCPAAAAAA==.Window:BAAALgADCgUJBQABLgAECgcJIAAQAKYeAA==.',
Wm='Wmdplague:BAAALgADCgYJBgAAAA==.',
Wo='Wolf:BAABLgAECn8wAAIEAAkJPhmrAgDSAQAEAAkJPhmrAgDSAQAAAA==.Wolfton:BAAALgAECgMJAwAAAA==.Woodtique:BAAALgAECgQJDgAAAA==.',
Wr='Wrekkit:BAAALgAECgkJEQAAAA==.',
Wy='Wylian:BAAALgAECgIJAgAAAA==.',
Xa='Xaeri:BAAALgADCgMJBAAAAA==.Xameris:BAAALgADCgEJAQAAAA==.Xandercruise:BAABLgAECn8UAAMYAAgJIhvAHQBTAgAYAAgJIhvAHQBTAgAZAAMJrAJgdABtAAAAAA==.',
Xe='Xelgoth:BAAALgADCgcJBgAAAA==.Xelphie:BAAALgADCgUJBQAAAA==.',
Xi='Xiia:BAAALgAECgIJAgABLgAECgQJBQACAAAAAA==.',
Xu='Xuchilbara:BAABLgAECn8eAAIaAAgJuRojCwALAgAaAAgJuRojCwALAgAAAA==.',
Xy='Xyro:BAAALgAECgUJBQABLgAFFAMJBgAVAM0UAA==.',
Ya='Yafool:BAAALgAECgEJAQABLgAFFAIJBgAfAOARAA==.Yamato:BAAALgAECgcJDQAAAA==.Yarina:BAAALgAECggJDQAAAA==.',
Za='Zaledron:BAACLgAFFH8FAAIVAAIJ4Rp+VwCjAAAVAAIJ4Rp+VwCjAAAuAAQKfyMAAhUACAlwIEcKAH4BABUACAlwIEcKAH4BAAAA.Zapnasty:BAAALgADCgcJBgAAAA==.',
Ze='Zenno:BAABLgAECn8sAAMfAAkJBxOwEACoAQAfAAkJBxOwEACoAQASAAMJVgiBtgBeAAAAAA==.Zevorcia:BAAALgAECgMJAwAAAA==.',
Zh='Zhades:BAACLgAFFH8lAAMVAAUJXB1dRABsAQAVAAUJXB1dRABsAQAUAAMJ/RW9CwDUAAAuAAQKf0gAAxUACQmmJY8HADkDABUACQmmJY8HADkDABQACAlQIf0DAJcCAAAA.Zhandaria:BAAALgAECgQJBwAAAA==.Zhandraia:BAAALgADCgUJBQAAAA==.Zhort:BAAALgAECgIJAwAAAA==.Zhulodok:BAAALgADCgMJAwAAAA==.',
Zi='Zioki:BAAALgAECgMJBAAAAA==.',
Zm='Zmrfister:BAAALgAECgYJBgABLgAFFAUJJQAVAFwdAA==.',
Zo='Zodgul:BAAALgAECgQJBAAAAA==.Zomby:BAACLgAFFH8IAAIVAAMJXA6KpwDMAAAVAAMJXA6KpwDMAAAuAAQKfxkABBUABgk/GtkLAF8BABUABgkaGNkLAF8BABQABQnTG5MDAEcBABMAAQldH18RAFUAAAEuAAUUBgkQAAwA7xEA.',
Zp='Zpersephone:BAABLgAECn8cAAIKAAcJDxMjaQBqAQAKAAcJDxMjaQBqAQABLgAFFAUJJQAVAFwdAA==.',
Zr='Zrii:BAAALgAECgkJEQAAAA==.',
Zu='Zultan:BAACLgAFFH8XAAIKAAQJqQisNAC0AAAKAAQJqQisNAC0AAAuAAQKf0MAAwoACQnKGQsgAGUCAAoACQnKGQsgAGUCAAkAAglmBBtIABkAAAAA.Zurrik:BAACLgAFFH8LAAMNAAQJTwYRMQC+AAANAAQJEgQRMQC+AAAEAAMJYQZ/KgBxAAAuAAQKfz4AAw0ACQm0EuggAMIBAA0ACQnwEeggAMIBAAQAAgn+E0NNAHcAAAAA.',
Zy='Zynofhealth:BAAALgADCgUJAwAAAA==.',
['Çõ']='Çõîñflïp:BAAALgADCgcJHAAAAA==.',
['Ðr']='Ðream:BAACLgAFFH8GAAInAAMJqBTYEgDjAAAnAAMJqBTYEgDjAAAuAAQKfycAAycACAmEHzsJAPUCACcACAmEHzsJAPUCABYAAwkjGQ2ZADYAAAAA.',
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
