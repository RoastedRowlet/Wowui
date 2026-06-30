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

local lookup = {'Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Druid-Guardian','Paladin-Holy','Warrior-Fury','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Monk-Mistweaver','Shaman-Restoration','DeathKnight-Blood','DeathKnight-Unholy','Monk-Windwalker','Warrior-Protection','Hunter-BeastMastery','Druid-Restoration','Druid-Feral','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Frost','Rogue-Subtlety','Evoker-Augmentation','Evoker-Preservation','Shaman-Enhancement','Druid-Balance','Warrior-Arms','Mage-Frost','Priest-Shadow','Priest-Discipline','Priest-Holy','Shaman-Elemental','Mage-Arcane','Rogue-Assassination','Monk-Brewmaster','Evoker-Devastation','Mage-Fire',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abberleigh:BAAALgAFFAMJAwAAAA==.',
Ad='Adonya:BAAALgADCgIJAQAAAA==.',
Ae='Aelgagar:BAAALgAECgYJEAAAAA==.Aelirina:BAAALgAECgMJAwAAAA==.',
Ah='Ahamay:BAAALgADCgEJAgAAAA==.',
Ai='Ailde:BAAALgADCgkJDgAAAA==.',
Ak='Akshhan:BAABLgAFFH8IAAIBAAUJlxBKSQAaAQABAAUJlxBKSQAaAQAAAA==.',
Al='Alania:BAAALgADCgYJCAAAAA==.Alaraa:BAABLgAECn8iAAMCAAcJkyEWCQBCAgACAAcJkyEWCQBCAgABAAIJ4xVQMwF7AAABLgAECgIJAgADAAAAAA==.Alarlia:BAABLgAECn8jAAIEAAgJvgtkMQDlAAAEAAgJvgtkMQDlAAAAAA==.Alathor:BAAALgAECgEJAQAAAA==.Algonq:BAAALgAECgUJEwABLgAECgkJMwAFAGgFAA==.Alliesofevil:BAABLgAECn8nAAIGAAkJaxU+JgDGAQAGAAkJaxU+JgDGAQAAAA==.Allsar:BAABLgAECn8aAAIEAAkJnB07BgCeAgAEAAkJnB07BgCeAgAAAA==.Alsar:BAAALgAECgQJBwABLgAECgkJGgAEAJwdAA==.Alssar:BAAALgAECgYJCwAAAA==.Alstar:BAAALgAECgEJAgAAAA==.',
Am='Amathus:BAACLgAFFH8NAAQHAAUJPAqbAwCeAAAIAAQJywRzEACwAAAJAAMJ1gT5iwCtAAAHAAIJFQ6bAwCeAAAuAAQKf24ABAgACQlmGgcEAEgCAAgACQkaGgcEAEgCAAkACQmWFGtGAMcBAAcABQkNE8wCAMcAAAAA.Amaunet:BAAALgADCgUJBQAAAA==.',
An='Anahilis:BAAALgADCgcJCAAAAA==.Andarial:BAABLgAECn8ZAAIKAAgJcQ3lJwA9AQAKAAgJcQ3lJwA9AQAAAA==.Andella:BAAALgAECgIJAgAAAA==.Andreth:BAAALgAECggJEwAAAA==.Anoxyn:BAAALgAECgcJCQAAAA==.Anthe:BAAALgAECgQJDAAAAA==.Anzul:BAABLgAECn8yAAMBAAkJVCCUJAByAgABAAkJQh+UJAByAgACAAUJxB0TGgBIAQAAAA==.',
Ar='Araestirra:BAABLgAECn8tAAMIAAcJPg82FwDpAAAJAAcJBgc4qwDsAAAIAAYJwRA2FwDpAAAAAA==.Arcanmaggy:BAAALgADCgkJHgABLgAFFAUJGwAJAPoEAA==.Ardahh:BAAALgADCgQJBAAAAA==.Arnold:BAABLgAECn8XAAMLAAgJ6hSYCwCjAQALAAgJ6hSYCwCjAQAMAAEJagPLOgEbAAABLgAECgkJGgAEAJwdAA==.Arntdorn:BAAALgADCgEJAQAAAA==.Arroes:BAABLgAECn8ZAAINAAgJGB/qFgBiAgANAAgJGB/qFgBiAgAAAA==.',
As='Asahna:BAAALgAECgQJBAAAAA==.',
At='Atlas:BAAALgAECggJCgABLgAECgkJGgAEAJwdAA==.',
Au='Aurrell:BAAALgADCgcJBwAAAA==.',
Av='Avoid:BAAALgAECgMJAwAAAA==.',
Ay='Ayroona:BAABLgAECn8pAAIOAAkJOgpVTgB4AQAOAAkJOgpVTgB4AQAAAA==.',
Az='Azhol:BAAALgAECgQJBAAAAA==.',
Ba='Bacontotem:BAAALgADCgMJBQAAAA==.Baelhal:BAACLgAFFH8ZAAIPAAQJmB08FQBEAQAPAAQJmB08FQBEAQAuAAQKfzQAAg8ACQmaHUIOACYCAA8ACQmaHUIOACYCAAAA.Balka:BAAALgADCgYJCAAAAA==.Barbaydos:BAAALgADCggJCQAAAA==.Barenjager:BAAALgAECgEJAQAAAA==.Basement:BAABLgAECn8gAAIMAAcJph5iBABBAQAMAAcJph5iBABBAQAAAA==.',
Be='Beastnite:BAAALgADCgkJKQABLgAECgkJGgAQAM4LAA==.Bellaburger:BAABLgAFFH8IAAIRAAQJsgYfIgDOAAARAAQJsgYfIgDOAAAAAA==.Bellissidan:BAAALgAECgEJAwAAAA==.Benedin:BAAALgAECgYJDwABLgAECgkJRgAHALYgAA==.',
Bi='Bigpapapete:BAAALgAECgYJAwAAAA==.Bigtex:BAABLgAECn81AAMGAAkJewt+BAAPAQAGAAkJRwt+BAAPAQASAAMJgwzKPAB/AAAAAA==.Biped:BAABLgAECn8zAAIHAAkJPhNbCADkAQAHAAkJPhNbCADkAQAAAA==.Birill:BAAALgAECgEJAgAAAA==.Bishul:BAAALgAECggJCQAAAA==.',
Bl='Blackdeath:BAACLgAFFH8FAAIQAAIJSgmG6wB+AAAQAAIJSgmG6wB+AAAuAAQKfywAAhAACAnkGygJAPwAABAACAnkGygJAPwAAAAA.',
Bo='Bombarian:BAAALgAECgUJCwAAAA==.Bone:BAAALgAECgEJAQAAAA==.Boomstique:BAABLgAECn84AAITAAkJZByQAgAdAgATAAkJZByQAgAdAgAAAA==.Boondocka:BAABLgAECn81AAITAAkJwBqFHAB6AgATAAkJwBqFHAB6AgAAAA==.',
Br='Brewco:BAACLgAFFH8QAAIUAAQJoRbaLQD9AAAUAAQJoRbaLQD9AAAuAAQKfzkABBQACQkEHKYUAJACABQACQkEHKYUAJACABUABgnDG1YSAJYBAAQABQl6Dw49ALIAAAAA.Brewer:BAAALgAECgEJAQAAAA==.Brickmebtch:BAAALgAECgYJBgAAAA==.Bruda:BAAALgAECgIJAwAAAA==.Brutalís:BAABLgAECn8oAAITAAkJFhICPwDmAQATAAkJFhICPwDmAQAAAA==.',
Bt='Btrain:BAABLgAECn8hAAMCAAYJ3AqaMQCfAAABAAYJzQZa9ADFAAACAAUJgAyaMQCfAAAAAA==.',
['Bó']='Bóunty:BAABLgAECn8bAAQWAAcJwx8lHwCjAQAWAAcJrh0lHwCjAQATAAQJNx5HXgBNAQAXAAEJPgJtmAAeAAAAAA==.',
Ca='Camaryn:BAAALgADCgIJAgAAAA==.Canadia:BAAALgAECgQJBgAAAA==.Caritta:BAAALgAECgQJBAAAAA==.Catdaddan:BAAALgADCgYJBgAAAA==.Cattnip:BAAALgAECgEJAQAAAA==.Cavisch:BAABLgAECn9GAAMHAAkJtiAcAQD/AgAHAAkJtiAcAQD/AgAJAAkJWBi7OwDsAQAAAA==.',
Ce='Cedric:BAAALgAECgIJAgABLgAECgYJBgADAAAAAA==.Cenobité:BAABLgAECn8yAAIYAAkJKhi2AAC4AQAYAAkJKhi2AAC4AQAAAA==.Cerr:BAAALgAECgMJBAAAAA==.',
Ch='Chamber:BAAALgAECgYJCAABLgAECgcJIAAMAKYeAA==.Chantilly:BAAALgADCgYJDwAAAA==.Chaosmaster:BAAALgAECgMJAwAAAA==.Chardee:BAABLgAFFH8HAAIZAAMJlBUmDQAVAQAZAAMJlBUmDQAVAQAAAA==.Charmeleon:BAABLgAECn8UAAMaAAgJCRJ1QQAjAQAaAAgJCRJ1QQAjAQAbAAIJfAwbNABWAAAAAA==.Charmin:BAAALgADCgUJBQAAAA==.Chicka:BAAALgAECgIJAgABLgAECgYJCQADAAAAAA==.Chiff:BAAALgADCgUJAwAAAA==.Chilledog:BAAALgADCgQJBAAAAA==.Chip:BAAALgAECgMJBgAAAA==.',
Ci='Cirax:BAABLgAECn8qAAITAAgJdBcvPgDpAQATAAgJdBcvPgDpAQAAAA==.Cirin:BAAALgADCgEJAQAAAA==.Citruscoolin:BAAALgAECgEJAQAAAA==.',
Cl='Cleetess:BAAALgAECgEJAQAAAA==.Clenton:BAABLgAECn9nAAMCAAkJ9gz8AQAwAQACAAkJlQv8AQAwAQABAAgJCQhFrwAgAQAAAA==.Clipper:BAAALgADCgYJBgAAAA==.',
Co='Cobrakai:BAAALgAECgIJAgAAAA==.Cowboyup:BAAALgADCgYJBgAAAA==.',
Cr='Crichton:BAACLgAFFH8TAAIMAAQJ9Rl5PgAtAQAMAAQJ9Rl5PgAtAQAuAAQKfzIAAgwACQm0IYIMAOECAAwACQm0IYIMAOECAAAA.Cronnan:BAAALgAECgUJBQAAAA==.Crowford:BAABLgAECn81AAITAAkJPBMzCQAsAQATAAkJPBMzCQAsAQAAAA==.',
Cy='Cyris:BAAALgAECgQJBwABLgAECgkJPAAcAAYGAA==.',
['Cá']='Cástle:BAAALgAECgEJAQABLgAECgcJIAAMAKYeAA==.',
Da='Daemonfaust:BAAALgAECgYJDwAAAA==.Daevahna:BAAALgADCgYJBgAAAA==.Dahtty:BAAALgAECgYJBwAAAA==.Dak:BAABLgAECn8lAAIQAAkJWxe1MAA8AgAQAAkJWxe1MAA8AgABLgAECggJGwABAI0YAA==.Daksclaw:BAAALgAECgYJBgABLgAECggJGwABAI0YAA==.Daksmash:BAAALgAECgUJCAABLgAECggJGwABAI0YAA==.Dakstab:BAAALgADCgkJCQAAAA==.Dalsar:BAABLgAECn8UAAMEAAgJywfxNwDHAAAEAAgJywfxNwDHAAAUAAQJKAkUCACFAAAAAA==.Darkbrew:BAAALgADCgYJCAABLgAECgkJNAACAGwhAA==.Darkfes:BAAALgAECgEJAQAAAA==.Darkmiza:BAACLgAFFH8bAAIJAAUJ+gRnbgDlAAAJAAUJ+gRnbgDlAAAuAAQKfzsAAwkACAl1EVJlAHMBAAkACAl1EVJlAHMBAAgAAglDC0lYAGYAAAAA.Darkseer:BAAALgAFFAIJBAAAAA==.Darthbluto:BAAALgAECgUJDQABLgAECgYJDwADAAAAAA==.Dasham:BAAALgAECgQJBAAAAA==.Daymann:BAABLgAECn8iAAIBAAkJHRa8SQDpAQABAAkJHRa8SQDpAQAAAA==.',
De='Deadazz:BAAALgADCgYJCgAAAA==.Deadmangalad:BAABLgAECn8sAAMYAAkJIgrfFQAqAQAYAAkJIgrfFQAqAQAPAAEJFATyaQAWAAAAAA==.Deathnotes:BAAALgADCgEJAQAAAA==.Deathquina:BAAALgAECgMJAwAAAA==.Deathtickle:BAAALgAECgcJAwAAAA==.Deedees:BAABLgAECn8eAAIdAAgJ5QZ8QwD/AAAdAAgJ5QZ8QwD/AAAAAA==.Demonbo:BAABLgAECn8aAAIMAAgJiBQUZABfAQAMAAgJiBQUZABfAQAAAA==.Demondrink:BAAALgAECgQJBgAAAA==.Demonhandler:BAAALgADCggJDwAAAA==.Deo:BAACLgAFFH8YAAMGAAQJGiDkEQB4AQAGAAQJGiDkEQB4AQAeAAMJMBTPKADKAAAuAAQKfz8AAwYACQkmJAAEACYDAAYACQkmJAAEACYDAB4AAgmSDeVjAFoAAAAA.Depression:BAAALgADCgUJBQAAAA==.Derpixion:BAABLgAECn8tAAMTAAgJYhlFJwAcAgATAAgJYhlFJwAcAgAWAAUJYQtJPgDSAAAAAA==.Dessirius:BAAALgAECgEJAQAAAA==.Dethphalanax:BAAALgADCgUJCQAAAA==.',
Di='Dies:BAAALgAECgkJBAAAAA==.Digbie:BAAALgADCgYJBwAAAA==.Digs:BAAALgADCgMJAwAAAA==.Dirtnåp:BAAALgAECgUJDQAAAA==.Diskbänk:BAAALgAECgUJBwAAAA==.',
Dk='Dkho:BAACLgAFFH8FAAIfAAMJ7gNqkwCuAAAfAAMJ7gNqkwCuAAAuAAQKfxUAAh8ACAnCDbV/AHgBAB8ACAnCDbV/AHgBAAAA.',
Dr='Drago:BAAALgAECgEJBAAAAA==.Dragontoast:BAAALgAECggJDwAAAA==.Dral:BAEALgADCgkJKAAAAA==.Draygun:BAAALgAECgcJBwABLgAFFAQJGAAGABogAA==.Drphilyobody:BAABLgAECn8cAAIQAAcJCQhMsgARAQAQAAcJCQhMsgARAQAAAA==.Drui:BAABLgAECn8dAAIdAAgJsQ4dNgBkAQAdAAgJsQ4dNgBkAQAAAA==.Druidïan:BAAALgAECgQJBQAAAA==.',
Du='Duelittle:BAABLgAECn8qAAIgAAcJmQ3uBADhAAAgAAcJmQ3uBADhAAAAAA==.',
Dy='Dynwor:BAAALgAECgEJAgAAAA==.',
['Dé']='Dérailed:BAAALgAECgUJEgAAAA==.',
['Dî']='Dîz:BAAALgADCgEJAQAAAA==.',
Ea='Easme:BAABLgAECn8jAAMWAAkJughLHQCyAQAWAAkJughLHQCyAQAXAAUJRANPYgC3AAAAAA==.Eatmyfrontal:BAABLgAECn86AAIfAAkJPxoAPwAgAgAfAAkJPxoAPwAgAgAAAA==.',
Eb='Ebbola:BAAALgADCgcJDgAAAA==.Ebon:BAAALgAECgMJAwABLgAECggJDAADAAAAAA==.',
Eh='Ehsinat:BAAALgADCgYJBgAAAA==.',
El='Elaraa:BAAALgAECgYJBwAAAA==.Elaric:BAAALgAECgYJBgAAAA==.Elger:BAAALgADCgEJAgAAAA==.Elvi:BAAALgAECgEJAQAAAA==.',
Em='Emory:BAAALgADCgEJAQAAAA==.',
En='Engi:BAAALgAECgcJDAAAAA==.',
Ep='Epikrate:BAABLgAECn8fAAMJAAgJURl8QADbAQAJAAcJIRl8QADbAQAIAAMJ4hiqSACUAAAAAA==.',
Es='Escaper:BAABLgAECn84AAIYAAkJcxLOCwC7AQAYAAkJcxLOCwC7AQAAAA==.',
Ex='Extrema:BAAALgAECggJDwAAAA==.',
Ez='Ezsdruid:BAAALgAECgkJCQAAAA==.',
Fa='Faesha:BAAALgAECgEJAQAAAA==.Fallenash:BAAALgADCgMJAwABLgAFFAQJFgAfAGsfAA==.Fallenembers:BAACLgAFFH8WAAIfAAQJax/0QwBhAQAfAAQJax/0QwBhAQAuAAQKfzsAAh8ACQlJJb8GAEsDAB8ACQlJJb8GAEsDAAAA.Famine:BAABLgAECn8dAAMQAAgJ0AWlvAACAQAQAAgJwwSlvAACAQAYAAUJzAf7DADfAAAAAA==.Farquaadtwo:BAAALgAECgIJAgAAAA==.',
Fe='Fearofthdark:BAAALgADCgEJAQAAAA==.',
Ff='Fflar:BAAALgADCgUJBQABLgAECgkJAgADAAAAAA==.',
Fh='Fhait:BAAALgAECgUJEQABLgAECgkJNAARAHkLAA==.',
Fi='Firsttimepvp:BAACLgAFFH8HAAIZAAIJJg3xNQCJAAAZAAIJJg3xNQCJAAAuAAQKfx4AAhkACQnaE6kUAPwBABkACQnaE6kUAPwBAAAA.',
Fl='Flow:BAAALgADCgYJBgAAAA==.',
Fr='Frenchtoast:BAAALgAECgIJAgAAAA==.Frostyflaker:BAAALgAECgUJDAAAAA==.',
Ga='Gaiã:BAAALgADCgEJAgAAAA==.Galadan:BAAALgAECgUJEwABLgAECgkJLAAYACIKAA==.Garrekton:BAAALgADCgIJAQABLgAECgkJRgAHALYgAA==.Gaskelmarg:BAAALgAECgUJDwAAAA==.',
Ge='Gellane:BAAALgAECgMJAwAAAA==.',
Gh='Ghosty:BAABLgAECn8hAAQhAAkJIRWWHwDRAQAhAAkJsRGWHwDRAQAiAAcJpAuKTgD+AAAgAAEJcAEanAAXAAAAAA==.Ghuun:BAAALgADCgEJAgABLgAFFAMJCAANAAoMAA==.',
Gi='Gigaweed:BAABLgAFFH8IAAINAAMJCgx/RQCOAAANAAMJCgx/RQCOAAAAAA==.',
Go='Goblinlayer:BAAALgAECgYJEwAAAA==.Goldtusk:BAABLgAECn8iAAIVAAkJEBVbDgDQAQAVAAkJEBVbDgDQAQAAAA==.Gooey:BAAALgADCggJDgAAAA==.Gostann:BAABLgAECn8mAAIJAAkJlRclJwBAAgAJAAkJlRclJwBAAgAAAA==.',
Gr='Grayparser:BAAALgADCgYJCQAAAA==.Grimsly:BAAALgAECgEJAQAAAA==.Grundler:BAAALgAFFAEJAQAAAA==.Gryphone:BAAALgADCgkJEAAAAA==.',
Gu='Gurinendo:BAAALgAECgEJAgAAAA==.Gustwin:BAAALgAECgQJBgAAAA==.',
['Gà']='Gàins:BAAALgAECgMJAwABLgAECgkJNAACAGwhAA==.',
Ha='Hakmud:BAAALgADCgYJCwAAAA==.Halsin:BAAALgADCgMJAwABLgAECggJIQAjAD0aAA==.Hamshammy:BAAALgAECgEJAQAAAA==.',
He='Heftydin:BAAALgAECgMJCQAAAA==.Heftymists:BAAALgAECgUJBQAAAA==.Heftystomp:BAAALgADCgUJBQAAAA==.Heftyvoid:BAAALgADCgEJAQAAAA==.Hela:BAAALgADCgcJBwAAAA==.Hercyderc:BAAALgAECgEJAQABLgAFFAIJBQAMADYgAA==.Hettokal:BAAALgAECgcJCQAAAA==.Heyitsjimbo:BAAALgADCgUJCQAAAA==.',
Ho='Holierhtanu:BAAALgADCgQJBwAAAA==.Holyhellion:BAABLgAECn8dAAIMAAkJchEFRQC4AQAMAAkJchEFRQC4AQAAAA==.Hondojoe:BAACLgAFFH8YAAIiAAQJvx5lDwBbAQAiAAQJvx5lDwBbAQAuAAQKfzsAAyIACQnuIEoLAJsCACIACQnuIEoLAJsCACEAAgnYBv1uAE0AAAAA.Honeydrake:BAAALgAECgYJCAAAAA==.Hopewell:BAABLgAECn8zAAIFAAkJaAUSRgAnAQAFAAkJaAUSRgAnAQAAAA==.',
Hu='Huginn:BAAALgADCgEJAQAAAA==.Hugnsnuggle:BAABLgAECn80AAILAAkJCAtEAQAoAQALAAkJCAtEAQAoAQABLgAECgkJNAARAHkLAA==.Huhu:BAABLgAECn8ZAAIGAAkJrxRhKwCnAQAGAAkJrxRhKwCnAQAAAA==.Huma:BAAALgAECgYJEAABLgAFFAQJCgATAAAOAA==.Hundreg:BAAALgADCgYJBQAAAA==.',
Ib='Ibn:BAABLgAECn8sAAIeAAkJBws1HwBkAQAeAAkJBws1HwBkAQAAAA==.',
Ic='Icyhot:BAAALgAECgMJBAAAAA==.',
Id='Ideal:BAAALgADCgYJDAAAAA==.',
Il='Illaris:BAAALgADCgIJAgAAAA==.',
In='Infiniity:BAAALgAECgMJCQAAAA==.Inksmear:BAAALgAECgEJAQAAAA==.',
Ir='Irielle:BAAALgAECgUJEAAAAA==.',
Is='Ishanllin:BAAALgAECgIJAgAAAA==.',
Iv='Ivarurngamet:BAABLgAECn8iAAIMAAkJyRfaLgALAgAMAAkJyRfaLgALAgAAAA==.Ivylyn:BAAALgAECgkJDgAAAA==.',
Ix='Ixiyá:BAABLgAECn89AAMOAAkJNCNtBABxAwAOAAkJNCNtBABxAwAjAAEJzghXrgAqAAAAAA==.Ixií:BAAALgAECgEJAwAAAA==.Ixì:BAABLgAECn8XAAIUAAcJ1x31IQA4AgAUAAcJ1x31IQA4AgAAAA==.',
Ja='Jakbequick:BAAALgAECgEJAQAAAA==.Jakeyprogue:BAAALgAFFAIJAwABLgAFFAIJBgAQAL4cAA==.Jakota:BAAALgADCgkJFAAAAA==.Jakskeleton:BAABLgAECn8fAAIPAAgJ2xoYEAAKAgAPAAgJ2xoYEAAKAgAAAA==.Jarobus:BAAALgAECgYJDgAAAA==.Jay:BAAALgADCgEJAQAAAA==.Jaynamir:BAAALgAECgYJEwAAAA==.Jayp:BAAALgAECgMJAwAAAA==.',
Jb='Jbernn:BAAALgAECgEJAQAAAA==.',
Je='Jeamica:BAAALgADCgcJCgAAAA==.',
Jo='Joemacho:BAAALgAECgcJEwABLgAFFAQJGAAiAL8eAA==.Joshtee:BAAALgAECgMJBQAAAA==.Joslyn:BAAALgAECgQJBQAAAA==.Jourdan:BAAALgADCgcJDQAAAA==.',
Ju='Judax:BAACLgAFFH8HAAIjAAMJaQ8FNwCyAAAjAAMJaQ8FNwCyAAAuAAQKfz0AAiMACQm0GyUTAFUCACMACQm0GyUTAFUCAAAA.Justagirl:BAABLgAECn80AAIRAAkJeQvrMwA0AQARAAkJeQvrMwA0AQAAAA==.Justiceboyd:BAAALgADCgMJAwAAAA==.Juti:BAAALgAECgQJCgAAAA==.',
Jy='Jymion:BAAALgADCgEJAQAAAA==.',
['Jú']='Júun:BAAALgADCgEJAQAAAA==.',
Ka='Kadooka:BAABLgAECn8lAAITAAgJPBmzCQAhAQATAAgJPBmzCQAhAQAAAA==.Kahlyn:BAAALgAECgYJCwAAAA==.Kajax:BAABLgAECn8qAAIZAAgJISMwCAANAwAZAAgJISMwCAANAwAAAA==.Kaldaran:BAABLgAECn8UAAMPAAgJQhrKGwB+AQAPAAgJQhrKGwB+AQAQAAIJtQTrUwFOAAAAAA==.Kallan:BAAALgAECgQJBAABLgAECgkJNAACAGwhAA==.Kalleigh:BAAALgADCgQJBAABLgAECgkJPAAcAAYGAA==.Karen:BAAALgADCgcJHAAAAA==.Karinn:BAAALgADCgEJAQAAAA==.Karne:BAAALgADCgYJBgAAAA==.Katira:BAAALgAECgEJAQAAAA==.Kazarath:BAAALgADCgUJBQAAAA==.',
Ke='Keeganw:BAABLgAECn8fAAMPAAYJThuSJgAfAQAPAAYJThuSJgAfAQAQAAEJKRKKIwA7AAAAAA==.Keelay:BAABLgAECn9GAAIFAAkJ+B9pCgDlAgAFAAkJ+B9pCgDlAgAAAA==.',
Kh='Kheegorn:BAABLgAECn8bAAIBAAgJjRhqTwDzAQABAAgJjRhqTwDzAQAAAA==.Khyla:BAAALgAECgEJAQAAAA==.',
Ki='Killua:BAAALgADCgYJBgABLgADCgcJCwADAAAAAA==.Kimiko:BAAALgAECgcJEAAAAA==.',
Kl='Klaw:BAAALgAECgQJBAABLgAECggJKgAZACEjAA==.',
Ko='Koffcmorbius:BAAALgAECgMJAwAAAA==.Koriban:BAABLgAECn8lAAIfAAkJaA69aQCoAQAfAAkJaA69aQCoAQAAAA==.Korreban:BAAALgAECgYJBgABLgAECgkJJQAfAGgOAA==.',
Kr='Kra:BAAALgAECgEJAgABLgAFFAMJCAANAAoMAA==.Kraken:BAACLgAFFH8FAAIIAAMJ0Q2rDQDIAAAIAAMJ0Q2rDQDIAAAuAAQKfysAAggACQlzIvIAAAUDAAgACQlzIvIAAAUDAAEuAAUUAwkIAA0ACgwA.Krim:BAAALgADCgYJBgAAAA==.',
Ku='Kubb:BAABLgAECn88AAIcAAkJBgYbAgATAQAcAAkJBgYbAgATAQAAAA==.Kunst:BAAALgADCgEJAQAAAA==.',
Kw='Kweh:BAACLgAFFH8ZAAIVAAYJlh+sAQDcAQAVAAYJlh+sAQDcAQAuAAQKfy0AAxUACQk6IxoFAMACABUACQk6IxoFAMACAB0ABQkbDqZGAPEAAAAA.',
Ky='Kytrina:BAAALgAECgEJAQAAAA==.',
['Kê']='Kêlsen:BAAALgAECgUJBwAAAA==.',
La='Lachupacabra:BAAALgAECgEJAQAAAA==.Larrissa:BAABLgAECn8oAAMHAAkJ7AbZEwAyAQAHAAkJ7AbZEwAyAQAIAAEJggPhewAlAAAAAA==.Larry:BAABLgAFFH8SAAIMAAYJghRiPgAtAQAMAAYJghRiPgAtAQAAAA==.Laurlynn:BAAALgAECggJEQAAAA==.Lavina:BAAALgADCgUJBQAAAA==.',
Le='Lenwe:BAAALgAECgYJCgABLgAECgcJLQAiAGwOAA==.Lettuceprey:BAABLgAECn8yAAIiAAkJ8w5bBAD3AAAiAAkJ8w5bBAD3AAAAAA==.',
Li='Lierise:BAABLgAECn8RAAQQAAcJzxlHBQBcAQAQAAcJzxlHBQBcAQAPAAMJ5BCVPACfAAAYAAEJJxMhBwA7AAAAAA==.Lies:BAAALgADCgkJCQAAAA==.Lightsnipe:BAAALgAECgQJBAAAAA==.Lilkelp:BAAALgAECgYJBwAAAA==.Lilspazz:BAAALgADCgMJAwAAAA==.Lithiri:BAAALgAECgUJBgABLgAECggJHgAQAK0fAA==.',
Lo='Lockatute:BAAALgAECggJEAAAAA==.Lockdeath:BAAALgAECgQJCQAAAA==.Loric:BAAALgADCgkJCQAAAA==.Loxia:BAABLgAECn8VAAIIAAgJ7AxyEwAWAQAIAAgJ7AxyEwAWAQAAAA==.',
Lu='Lucille:BAACLgAFFH8FAAIfAAEJfAavQQBEAAAfAAEJfAavQQBEAAAuAAQKfx8AAh8ACAnjEbIJABcBAB8ACAnjEbIJABcBAAAA.Luckett:BAAALgADCgEJAQAAAA==.Lucrotia:BAAALgADCgQJBAAAAA==.Luukmosh:BAAALgAECgUJCQAAAA==.',
Ma='Maavarra:BAABLgAECn8rAAMVAAkJlBvfAACfAQAVAAkJlBvfAACfAQAUAAQJLRQoBQDYAAAAAA==.Madilyons:BAAALgADCgIJAgAAAA==.Madischa:BAAALgAECgcJEQAAAA==.Magicdance:BAACLgAFFH8JAAIjAAQJxQJnOACtAAAjAAQJxQJnOACtAAAuAAQKfzsAAw4ACQmEEUZLAIMBAA4ACQmEEUZLAIMBACMACQmeCq8FANMAAAAA.Magolthel:BAAALgADCgYJCQAAAA==.Maimgame:BAABLgAECn8WAAIVAAgJchK/CwACAgAVAAgJchK/CwACAgAAAA==.Majicbob:BAABLgAECn8hAAIjAAgJPRoSHgDxAQAjAAgJPRoSHgDxAQAAAA==.Maki:BAAALgAECggJEwAAAA==.Mansion:BAAALgADCgQJBgABLgAECgcJIAAMAKYeAA==.Marilune:BAAALgADCggJCQAAAA==.Marn:BAAALgADCgQJBAAAAA==.Marthran:BAAALgADCgIJAgAAAA==.Maxlin:BAAALgAECgEJAgAAAA==.',
Mc='Mctowlie:BAAALgAECgYJCAAAAA==.',
Me='Mehänemäntä:BAAALgAECggJDwAAAA==.Meldo:BAAALgADCggJDQAAAA==.Mellinessa:BAABLgAECn8aAAMYAAcJqBXJEwBAAQAQAAYJJRKQlABXAQAYAAUJWBXJEwBAAQAAAA==.Mena:BAAALgADCgUJBgAAAA==.Merixa:BAAALgADCgEJAQAAAA==.',
Mf='Mfdkidney:BAAALgAECgIJAgAAAA==.',
Mi='Midou:BAAALgAECgMJAwABLgAFFAQJCQAjAMUCAA==.Minthraxis:BAAALgADCgEJAQAAAA==.Misaun:BAAALgAECgEJAgAAAA==.Misericorde:BAACLgAFFH8QAAIRAAQJUyTRCACNAQARAAQJUyTRCACNAQAuAAQKfzwAAhEACQkYJqUBAF0DABEACQkYJqUBAF0DAAAA.Misstreater:BAABLgAECn8fAAMkAAgJdgYkCgDpAAAfAAcJZAUmzgD0AAAkAAcJyQYkCgDpAAAAAA==.',
Mo='Momentomori:BAABLgAECn8gAAIJAAkJvghkbwBcAQAJAAkJvghkbwBcAQAAAA==.Monbow:BAAALgAECgMJBwABLgAECggJGgAMAIgUAA==.Monocerotis:BAAALgAECgQJBAAAAA==.Morishima:BAACLgAFFH8XAAIZAAQJ6xmoFgBYAQAZAAQJ6xmoFgBYAQAuAAQKf08AAxkACQlkJPcCACIDABkACQlkJPcCACIDACUAAQkJFtklAD0AAAAA.Morthis:BAABLgAECn82AAMXAAkJXxGAAADMAQAXAAkJXxGAAADMAQAWAAMJWgM5WABMAAAAAA==.',
Mt='Mtpoccy:BAAALgADCgYJBgAAAA==.',
Mu='Multipàss:BAAALgADCgcJCgAAAA==.',
My='Mydarling:BAAALgAFFAIJAwAAAA==.Mymoon:BAAALgAECgIJAgAAAA==.Myris:BAACLgAFFH8FAAIQAAMJtw8IqADMAAAQAAMJtw8IqADMAAAuAAQKfywAAhAACQmpG3AnAGUCABAACQmpG3AnAGUCAAAA.',
Na='Narcan:BAAALgAECgUJDQAAAA==.Naturalchi:BAABLgAECn8wAAMRAAkJByWbAgBCAwARAAkJiiSbAgBCAwAmAAgJ8x5yDABuAgAAAA==.',
Nb='Nbi:BAAALgAECgEJAQAAAA==.',
Ne='Nefilion:BAABLgAFFH8GAAIQAAIJ7wsI6QB/AAAQAAIJ7wsI6QB/AAAAAA==.Nemas:BAABLgAECn8hAAICAAgJrxnuDgDVAQACAAgJrxnuDgDVAQAAAA==.Neverleft:BAAALgAECgUJCAAAAA==.Nezin:BAABLgAECn8tAAQaAAkJ0RYtAQC1AQAaAAkJjxUtAQC1AQAnAAYJJRNDDwAXAQAbAAIJuQ2jQABlAAAAAA==.',
Ni='Nightrun:BAAALgADCgcJCwAAAA==.Nightrunnêr:BAAALgAECgUJCwABLgAECgkJNAACAGwhAA==.Nineadin:BAACLgAFFH8TAAMBAAQJnwsQWAAAAQABAAQJnwsQWAAAAQAFAAQJkhVsBwD5AAAuAAQKfycAAwUACQmYHU0TAHgCAAUACQmYHU0TAHgCAAEAAgkjHZ0IAa4AAAAA.Nineshots:BAAALgAFFAMJBAABLgAFFAQJEwABAJ8LAA==.Ninetoads:BAAALgAECgcJDQABLgAFFAQJEwABAJ8LAA==.Nirvanas:BAABLgAECn8dAAIVAAgJ/A10HQAeAQAVAAgJ/A10HQAeAQAAAA==.Niyoko:BAAALgADCgcJBwAAAA==.',
No='Nomik:BAABLgAECn8tAAMiAAcJbA6KNwAgAQAiAAcJbA6KNwAgAQAgAAYJ1Qe6YwCMAAAAAA==.Nonah:BAAALgADCgEJAgAAAA==.North:BAAALgAECggJCAAAAA==.',
Nu='Nuke:BAABLgAECn8VAAITAAQJvBkkDAD2AAATAAQJvBkkDAD2AAAAAA==.Nullspace:BAABLgAECn8qAAMiAAkJXhq+FAAvAgAiAAkJXhq+FAAvAgAgAAMJAQzxBwCUAAAAAA==.Nunskee:BAAALgAECgQJBAAAAA==.',
['Ní']='Níght:BAABLgAECn85AAIEAAgJKRdYFQCqAQAEAAgJKRdYFQCqAQAAAA==.',
Oa='Oaken:BAAALgADCgkJCgAAAA==.',
Oc='Occultivated:BAAALgAECgQJBgAAAA==.',
Od='Oddtotem:BAAALgADCgMJAwAAAA==.',
Oh='Ohhk:BAAALgAECgMJAwAAAA==.',
Om='Ommû:BAAALgAECgMJCAAAAA==.',
Op='Op:BAAALgAECgIJAgABLgAFFAMJCAANAAoMAA==.',
Or='Orillar:BAAALgADCgEJAQAAAA==.',
Pa='Pakeydk:BAABLgAFFH8GAAIQAAIJvhxWxgCfAAAQAAIJvhxWxgCfAAAAAA==.Palacia:BAAALgAECggJEQAAAA==.Pancakedealr:BAAALgAECgUJEAAAAA==.Pancakeeater:BAAALgAECgUJCgAAAA==.Pappabeary:BAAALgADCgEJAQAAAA==.',
Pe='Peaches:BAAALgAECgEJAQAAAA==.Peerow:BAAALgADCgMJAwAAAA==.Permelia:BAAALgADCgYJBgAAAA==.Petrichorica:BAAALgAECgcJEgAAAA==.Peí:BAAALgAECgEJAQAAAA==.',
Ph='Phatjake:BAAALgADCgYJBgAAAA==.',
Pi='Ping:BAABLgAFFH8GAAINAAYJ7xQuBADzAQANAAYJ7xQuBADzAQAAAA==.Pintobeans:BAABLgAECn8XAAITAAkJlQVJdwBRAQATAAkJlQVJdwBRAQAAAA==.',
Pl='Plutonix:BAAALgAECgMJBQAAAA==.',
Pr='Preachêr:BAAALgAECgQJCQABLgAECgkJNAACAGwhAA==.Prohteus:BAAALgAECgEJAQABLgAECgMJBQADAAAAAA==.',
Pu='Puuhceew:BAABLgAECn8gAAIiAAgJUw61NgAlAQAiAAgJUw61NgAlAQAAAA==.',
Qu='Quan:BAEALgADCgcJCQABLgADCgkJKAADAAAAAA==.Quelaag:BAAALgADCgQJBAAAAA==.Quenthel:BAAALgAECgkJAgAAAA==.Quiescent:BAABLgAECn8pAAIMAAgJdRr2KQAiAgAMAAgJdRr2KQAiAgAAAA==.Quina:BAAALgAECgQJBwAAAA==.',
Ra='Ragingtides:BAAALgADCgEJAQAAAA==.Rainera:BAABLgAECn8uAAMHAAkJfSS8AQDWAgAHAAkJfSS8AQDWAgAJAAEJAxH1OgE1AAABLgAFFAcJGAALAPMjAA==.Ramanas:BAABLgAECn8ZAAMgAAgJNBLOLwBgAQAgAAcJjRLOLwBgAQAhAAYJnBGILQAxAQAAAA==.Ramrod:BAAALgAECgIJAwAAAA==.Randomizwe:BAABLgAECn8uAAIBAAkJtB5EIwB4AgABAAkJtB5EIwB4AgAAAA==.Raspet:BAAALgADCgIJAgAAAA==.Rattles:BAAALgADCgcJCwAAAA==.Raynu:BAAALgAECgEJAwAAAA==.Raín:BAAALgAECggJDwAAAA==.',
Re='Relearning:BAABLgAECn8xAAIJAAkJnA8yBwDyAAAJAAkJnA8yBwDyAAAAAA==.Relyn:BAABLgAECn8UAAIMAAgJWQchigAMAQAMAAgJWQchigAMAQAAAA==.Resurgencê:BAABLgAECn80AAICAAkJbCFGAACjAgACAAkJbCFGAACjAgAAAA==.Retalltheway:BAAALgADCgEJAQAAAA==.',
Ri='Riggler:BAAALgAECgcJBwAAAA==.Riordan:BAABLgAECn8mAAMBAAgJ6BQykgBOAQABAAcJChQykgBOAQACAAQJ9xPgJQDnAAAAAA==.',
Ro='Rohz:BAAALgADCgIJAgABLgAECgcJIAAMAKYeAA==.Rojeton:BAAALgADCgUJBwAAAA==.Rosenth:BAAALgADCggJEwAAAA==.Rotandroll:BAAALgAECgcJDwAAAA==.Rothema:BAABLgAECn8iAAMOAAkJWAfskwCvAAAOAAcJzQPskwCvAAAjAAgJkwg1CQCBAAAAAA==.Routh:BAAALgAECgEJAQAAAA==.',
Rw='Rwlmaster:BAABLgAECn89AAIPAAkJSBuuDwAQAgAPAAkJSBuuDwAQAgAAAA==.',
Ry='Rynzia:BAACLgAFFH8ZAAMnAAQJMhkiBAAtAQAaAAQJMhmcJwAuAQAnAAQJMxMiBAAtAQAuAAQKf0cABCcACQngIa0BANECACcACQktH60BANECABoACQnJIGEMAJUCABsABwnnErsSAJ0BAAAA.',
Sa='Sadabacus:BAAALgAECgEJAgAAAA==.Sagetempest:BAAALgADCgEJAQAAAA==.Sagittarian:BAAALgADCgUJBwAAAA==.Sandwiches:BAAALgAECggJEwAAAA==.Santose:BAAALgAECgIJAgAAAA==.Sarya:BAAALgAECgQJBAABLgAECgkJAgADAAAAAA==.',
Sc='Scalyt:BAAALgADCgYJBgAAAA==.Scerra:BAABLgAECn8mAAIQAAkJExBnTgDXAQAQAAkJExBnTgDXAQAAAA==.Schmerz:BAAALgADCgUJBQAAAA==.Scridderz:BAAALgAECgMJBgAAAA==.',
Se='Sendia:BAAALgADCgQJBAABLgAECgIJAgADAAAAAA==.Sephiros:BAAALgADCgIJAgAAAA==.Seru:BAAALgAECggJEwAAAA==.Seta:BAABLgAECn8bAAIMAAgJ3xNeQwDmAQAMAAgJ3xNeQwDmAQAAAA==.Seviran:BAAALgADCgIJAwAAAA==.',
Sh='Shakeyjams:BAAALgADCgYJBgABLgAFFAIJBgAQAL4cAA==.Shamantha:BAAALgADCgEJAQAAAA==.Shamarha:BAABLgAECn8dAAIOAAgJaBoKMwDmAQAOAAgJaBoKMwDmAQAAAA==.Shaolin:BAAALgAECgQJBAAAAA==.Sharriavolf:BAABLgAECn9FAAQJAAkJxCOLQADbAQAJAAcJ7CGLQADbAQAIAAQJ+CMLIABSAQAHAAEJAAB7IwBkAAAAAA==.Shato:BAAALgAECgYJCQAAAA==.Sheoth:BAAALgADCgQJBAAAAA==.Shiori:BAAALgAECgcJEAAAAA==.Shortmedic:BAAALgAECgQJBAAAAA==.Shotzys:BAAALgAECgYJEgAAAA==.Shrieve:BAAALgAECgMJAwAAAA==.Shurg:BAAALgAECgQJBAAAAA==.',
Si='Sicarius:BAAALgADCgcJCgABLgAECgEJAgADAAAAAA==.Siggismund:BAABLgAECn8rAAIBAAkJKguWeAB9AQABAAkJKguWeAB9AQAAAA==.Simichaelton:BAACLgAFFH8NAAIfAAYJJg0xYQAfAQAfAAYJJg0xYQAfAQAuAAQKfxoAAh8ACQnDFFZJAP8BAB8ACQnDFFZJAP8BAAAA.Sinpal:BAABLgAFFH8LAAIBAAQJYBMkHgCvAAABAAQJYBMkHgCvAAAAAA==.Sinthea:BAAALgAECgkJAgAAAA==.Sioce:BAAALgADCgkJKgAAAA==.',
Sk='Skrobifu:BAAALgADCgQJAwAAAA==.',
Sl='Slickacitic:BAAALgAECgYJBwABLgAECgcJHwAOAAwLAA==.Slimselect:BAAALgADCgMJAwAAAA==.Slimt:BAAALgADCgMJAwAAAA==.Sloppyshids:BAAALgAECgcJCAAAAA==.Slur:BAAALgADCgIJAgABLgADCgYJBgADAAAAAA==.',
Sm='Smorroy:BAAALgADCgYJBgAAAA==.',
So='Softbakedhoj:BAABLgAECn8eAAIBAAgJ/BxdSQAGAgABAAgJ/BxdSQAGAgAAAA==.Sophrosyne:BAABLgAECn8sAAITAAkJhxvfLwAdAgATAAkJhxvfLwAdAgAAAA==.Souless:BAAALgAECgYJBgAAAA==.',
Sp='Spankie:BAAALgAECgQJBAAAAA==.Sparkness:BAAALgAECgMJAwAAAA==.Spartaaxd:BAABLgAECn8yAAIYAAkJkRDOAQAHAQAYAAkJkRDOAQAHAQAAAA==.Spookems:BAAALgAECgIJAgABLgAFFAMJAwADAAAAAA==.Spycy:BAABLgAECn8UAAIfAAkJ3BA3hQBtAQAfAAkJ3BA3hQBtAQAAAA==.',
St='Stagerrind:BAAALgAECgUJDQAAAA==.Starfall:BAAALgAECgkJAgAAAA==.Steiner:BAABLgAECn8qAAMFAAkJOwzhNAB+AQAFAAkJOwzhNAB+AQABAAEJ9QcBtgEnAAAAAA==.Stinkyfrog:BAACLgAFFH8GAAIBAAMJxQzshgClAAABAAMJxQzshgClAAAuAAQKfyUAAgEACQlOIuALAAYDAAEACQlOIuALAAYDAAAA.Stovetop:BAAALgAECgEJAQABLgAECgUJBwADAAAAAA==.Stubmcbean:BAAALgADCggJCQABLgAECgkJPAAcAAYGAA==.Stunted:BAAALgAECgMJAwAAAA==.',
Su='Sugarfrost:BAABLgAECn8mAAIfAAkJOgs5pAA0AQAfAAkJOgs5pAA0AQAAAA==.Sugarseer:BAAALgAECgQJBAABLgAECgkJJgAfADoLAA==.Suka:BAAALgAECgUJEAAAAA==.Surok:BAAALgAECgYJDwAAAA==.',
Sw='Sweetleaf:BAAALgAECgUJCAAAAA==.Swiftleaf:BAAALgAECgcJDAAAAA==.',
Sy='Sylentcurse:BAABLgAECn8hAAIHAAgJDQutEQBKAQAHAAgJDQutEQBKAQABLgAECgkJKAATABYSAA==.Sylentstorm:BAABLgAECn8bAAMOAAgJVAPKgwDXAAAOAAgJVAPKgwDXAAAjAAEJAAAHyQAAAAABLgAECgkJKAATABYSAA==.Syleta:BAABLgAECn9LAAQWAAkJKiCaBADjAgAWAAkJ3h+aBADjAgATAAcJwxwNMADwAQAXAAYJCRNpRABEAQABLgAECgIJAgADAAAAAA==.',
Ta='Tabraxis:BAAALgAECgEJAQAAAA==.Tagalorc:BAABLgAECn8fAAMkAAkJPRVFAwD2AQAkAAkJPRVFAwD2AQAfAAEJ8QGigQEcAAAAAA==.Takamaki:BAAALgAECgEJAwAAAA==.Tanksbacon:BAABLgAECn8oAAMBAAkJgBnKMAA9AgABAAkJgBnKMAA9AgACAAQJtxKSLwCWAAAAAA==.Taylith:BAAALgAECgYJEgAAAA==.',
Te='Teana:BAACLgAFFH8GAAIYAAMJqgdMBgDEAAAYAAMJqgdMBgDEAAAuAAQKfyIAAhgACAnkD5MQAG0BABgACAnkD5MQAG0BAAAA.Teannev:BAAALgADCgYJBgAAAA==.Tempestas:BAAALgAECgEJAQAAAA==.Teraax:BAAALgADCgEJAQAAAA==.',
Th='Tharos:BAAALgAECgUJCgAAAA==.Thebrewco:BAAALgADCgMJAwABLgAFFAQJEAAUAKEWAA==.Thechadd:BAABLgAFFH8HAAIjAAcJaAPhNwCvAAAjAAcJaAPhNwCvAAAAAA==.Thelegendáry:BAACLgAFFH8OAAIOAAQJlhE/PADyAAAOAAQJlhE/PADyAAAuAAQKfxoAAg4ABgmWF0FKAFkBAA4ABgmWF0FKAFkBAAAA.Thetool:BAAALgAECgMJBAAAAA==.Thevileone:BAAALgAECggJCAABLgAFFAQJGQAPAJgdAA==.Thraine:BAAALgAECgYJCwAAAA==.',
Ti='Tinyshadowz:BAAALgAECgEJAQAAAA==.Tione:BAABLgAECn87AAMdAAkJQRz+EgA9AgAdAAgJMh3+EgA9AgAUAAkJFQuXVAA+AQAAAA==.Tireck:BAAALgADCggJCQAAAA==.',
To='Toriee:BAAALgAECgkJCQAAAA==.Tormented:BAAALgAECgMJAwAAAA==.Totembish:BAABLgAECn8gAAIjAAkJZAnaPABCAQAjAAkJZAnaPABCAQAAAA==.',
Tr='Treebear:BAAALgADCgcJDQAAAA==.Tremor:BAAALgADCgIJAgAAAA==.Trisstan:BAABLgAECn8sAAMfAAkJuAplkgBTAQAfAAkJuAplkgBTAQAoAAMJawEvDQBVAAAAAA==.Trucknly:BAAALgADCgMJAwAAAA==.',
Tu='Tundarian:BAAALgAECggJDwAAAA==.Tundie:BAAALgAFFAEJAQAAAA==.',
Tw='Twigz:BAAALgADCgcJBgAAAA==.',
Ty='Tyronicals:BAABLgAECn8iAAMfAAkJshvsOwAqAgAfAAkJkBjsOwAqAgAkAAUJHyAJBgDAAQAAAA==.Tyster:BAACLgAFFH8TAAIBAAQJqhNUEwDsAAABAAQJqhNUEwDsAAAuAAQKfyMAAwEACQl0FSBEAPoBAAEACQnGFCBEAPoBAAIAAQkbFgNKAEEAAAAA.',
['Tø']='Tørmëntëd:BAAALgAECgMJBAAAAA==.',
Ug='Ugotdusted:BAAALgADCgYJBgAAAA==.',
Uk='Ukyo:BAAALgADCgUJBgAAAA==.',
Ul='Ullidon:BAAALgAECgIJAgAAAA==.',
Um='Umbrã:BAAALgADCgEJAQAAAA==.',
Un='Unavoidably:BAAALgADCgIJAgAAAA==.Undol:BAAALgADCggJGwABLgAECgkJPAAcAAYGAA==.',
Ux='Uxe:BAAALgAFFAEJAQABLgAECgkJJAAmAFkaAA==.',
Uz='Uzu:BAABLgAECn8kAAMmAAkJWRqeJQCBAQAmAAkJWRqeJQCBAQARAAEJyhLTjQBDAAAAAA==.',
Va='Valios:BAAALgADCgcJBwAAAA==.Valorr:BAAALgAECgQJBAAAAA==.Vamp:BAABLgAECn8YAAIOAAgJxxbxLwDIAQAOAAgJxxbxLwDIAQAAAA==.Vandaldor:BAAALgAECgYJEQAAAA==.Vandrana:BAAALgAECgUJCQAAAA==.Vasalrius:BAAALgADCgIJAgAAAA==.Vasilli:BAAALgADCgYJDwAAAA==.',
Ve='Vedrix:BAAALgAECgcJBgAAAA==.Vellora:BAAALgADCgUJBQAAAA==.Veloth:BAACLgAFFH8cAAIfAAQJYhkEUAA+AQAfAAQJYhkEUAA+AQAuAAQKfzMAAh8ACQnwIh4iAJUCAB8ACQnwIh4iAJUCAAAA.Vexnyx:BAAALgADCgcJCAAAAA==.',
Vh='Vhitahni:BAAALgAECgMJAwAAAA==.',
Vi='Viggle:BAAALgADCggJCAABLgAECgkJNAACAGwhAA==.Vireaux:BAAALgADCgEJAQAAAA==.Viviro:BAAALgADCgcJDQAAAA==.',
Vl='Vll:BAABLgAECn8nAAMTAAkJtRsKKQA6AgATAAkJtRsKKQA6AgAWAAIJewTpKgBVAAABLgAECggJIgAKAO4iAA==.',
Vo='Voodoomike:BAAALgAECgIJAgAAAA==.',
Vy='Vynlorin:BAAALgAECgYJBgABLgAECgkJMgABAFQgAA==.',
Wa='Wanawa:BAAALgAECgMJAwABLgAECgkJIgAVABAVAA==.Wanghaf:BAAALgAECgYJDQAAAA==.Warhorne:BAAALgAECgEJAQABLgAECgkJIgAVABAVAA==.Warloque:BAAALgAECgMJAwAAAA==.Warthog:BAAALgADCgkJGQAAAA==.Waterbender:BAABLgAECn8ZAAIOAAkJRRqPGQB+AgAOAAkJRRqPGQB+AgAAAA==.',
We='Weechuup:BAAALgAECgMJAwAAAA==.Weleindon:BAAALgADCgMJAwAAAA==.',
Wi='Wifeotusk:BAAALgAECgkJEAAAAA==.Wiggle:BAAALgADCgMJAwAAAA==.Willmar:BAABLgAECn8hAAIBAAgJ2hY3UQDVAQABAAgJ2hY3UQDVAQAAAA==.Wilshaman:BAAALgAECgUJBgAAAA==.Window:BAAALgADCgUJBQABLgAECgcJIAAMAKYeAA==.',
Wm='Wmdplague:BAAALgADCgYJBgAAAA==.',
Wo='Wolf:BAABLgAECn8oAAIEAAkJNhc5EwDAAQAEAAkJNhc5EwDAAQAAAA==.Wolfton:BAAALgAECgMJAwAAAA==.Woodtique:BAAALgAECgMJBgAAAA==.',
Wr='Wrekkit:BAAALgAECggJDwAAAA==.',
Wy='Wylian:BAAALgAECgIJAgAAAA==.',
Xa='Xaeri:BAAALgADCgMJBAAAAA==.Xameris:BAAALgADCgEJAQAAAA==.Xandercruise:BAABLgAECn8UAAMTAAgJIhvAHQBTAgATAAgJIhvAHQBTAgAXAAMJrAJgdABtAAAAAA==.',
Xe='Xelgoth:BAAALgADCgcJBgAAAA==.Xelphie:BAAALgADCgUJBQAAAA==.',
Xu='Xuchilbara:BAABLgAECn8eAAIVAAgJuRojCwALAgAVAAgJuRojCwALAgAAAA==.',
Xy='Xyro:BAAALgAECgUJBQABLgAECggJGwABAI0YAA==.',
Ya='Yamato:BAAALgAECgcJDQAAAA==.',
Za='Zaledron:BAABLgAECn8eAAIQAAgJrR/FNQAoAgAQAAgJrR/FNQAoAgAAAA==.Zapnasty:BAAALgADCgcJBgAAAA==.',
Ze='Zenno:BAABLgAECn8qAAMcAAkJXxKwEACoAQAcAAkJXxKwEACoAQAOAAMJVgiBtgBeAAAAAA==.Zevorcia:BAAALgAECgMJAwAAAA==.',
Zh='Zhades:BAACLgAFFH8kAAMQAAUJXB35EABIAQAQAAUJXB35EABIAQAYAAMJ/RW1BADtAAAuAAQKf0YAAxAACQmiJY8HADkDABAACQmiJY8HADkDABgACAlQIf0DAJcCAAAA.Zhandaria:BAAALgAECgQJBwAAAA==.Zhandraia:BAAALgADCgUJBQAAAA==.Zhort:BAAALgAECgIJAwAAAA==.Zhulodok:BAAALgADCgMJAwAAAA==.',
Zi='Zioki:BAAALgADCgcJEgABLgAECgEJAgADAAAAAA==.',
Zm='Zmrfister:BAAALgAECgYJBgABLgAFFAUJJAAQAFwdAA==.',
Zo='Zodgul:BAAALgAECgQJBAAAAA==.Zomby:BAABLgAFFH8IAAIQAAMJXA6KpwDMAAAQAAMJXA6KpwDMAAABLgAFFAYJDQAfACYNAA==.',
Zp='Zpersephone:BAABLgAECn8cAAIJAAcJDxMjaQBqAQAJAAcJDxMjaQBqAQABLgAFFAUJJAAQAFwdAA==.',
Zr='Zrii:BAAALgAECggJCgAAAA==.',
Zu='Zultan:BAACLgAFFH8RAAIJAAQJawfsaADzAAAJAAQJawfsaADzAAAuAAQKf0MAAwkACQnKGZUCALcBAAkACQnKGZUCALcBAAgAAglmBBtIABkAAAAA.Zurrik:BAACLgAFFH8LAAMdAAQJTwYRMQC+AAAdAAQJEgQRMQC+AAAEAAMJYQZ/KgBxAAAuAAQKfz4AAx0ACQm0EuggAMIBAB0ACQnwEeggAMIBAAQAAgn+E0NNAHcAAAAA.',
Zy='Zynofhealth:BAAALgADCgUJAwAAAA==.',
['Çõ']='Çõîñflïp:BAAALgADCgcJHAAAAA==.',
['Ðr']='Ðream:BAACLgAFFH8GAAImAAMJqBTYEgDjAAAmAAMJqBTYEgDjAAAuAAQKfycAAyYACAmEHzsJAPUCACYACAmEHzsJAPUCABEAAwkjGQ2ZADYAAAAA.',
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
