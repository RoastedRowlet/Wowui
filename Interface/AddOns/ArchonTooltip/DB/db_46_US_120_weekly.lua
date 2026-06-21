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

local lookup = {'Paladin-Retribution','Paladin-Protection','Hunter-Survival','Druid-Guardian','Paladin-Holy','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Monk-Mistweaver','Shaman-Restoration','DeathKnight-Blood','DeathKnight-Unholy','Monk-Windwalker','Warrior-Protection','Hunter-BeastMastery','Druid-Restoration','Druid-Feral','Hunter-Marksmanship','Unknown-Unknown','DeathKnight-Frost','Rogue-Subtlety','Evoker-Augmentation','Evoker-Preservation','Shaman-Enhancement','Druid-Balance','Warrior-Arms','Mage-Frost','Priest-Shadow','Priest-Discipline','Priest-Holy','Shaman-Elemental','Mage-Arcane','Rogue-Assassination','Monk-Brewmaster','Evoker-Devastation','Mage-Fire',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abberleigh:BAAALgAFFAMJAwAAAA==.',
Ad='Adonya:BAAALgADCgIJAQAAAA==.',
Ae='Aelgagar:BAAALgAECgYJEAAAAA==.Aelirina:BAAALgAECgMJAwAAAA==.',
Ah='Ahamay:BAAALgADCgEJAgAAAA==.',
Ai='Ailde:BAAALgADCgkJDgAAAA==.',
Ak='Akshhan:BAABLgAFFH8IAAIBAAUJlxBVSQAaAQABAAUJlxBVSQAaAQAAAA==.',
Al='Alania:BAAALgADCgYJCAAAAA==.Alaraa:BAABLgAECn8gAAMCAAcJkyEWCQBCAgACAAcJkyEWCQBCAgABAAIJ4xVIMwF7AAABLgAECgkJSwADACogAA==.Alarlia:BAABLgAECn8jAAIEAAgJvgtiMQDlAAAEAAgJvgtiMQDlAAAAAA==.Alathor:BAAALgAECgEJAQAAAA==.Algonq:BAAALgAECgUJDwABLgAECgkJMgAFAGgFAA==.Alliesofevil:BAABLgAECn8kAAIGAAgJlxQ9JgDGAQAGAAgJlxQ9JgDGAQAAAA==.Allsar:BAABLgAECn8aAAIEAAkJnB07BgCeAgAEAAkJnB07BgCeAgAAAA==.Alsar:BAAALgAECgQJBwABLgAECgkJGgAEAJwdAA==.Alssar:BAAALgAECgYJCgAAAA==.Alstar:BAAALgAECgEJAgAAAA==.',
Am='Amathus:BAACLgAFFH8KAAMHAAUJ9AR5EACwAAAHAAQJywR5EACwAAAIAAMJ1gQLjACtAAAuAAQKf2kABAcACQlmGgcEAEgCAAcACQkaGgcEAEgCAAgACQmWFGlGAMcBAAkABAmnD7gbAOAAAAAA.Amaunet:BAAALgADCgUJBQAAAA==.',
An='Anahilis:BAAALgADCgcJCAAAAA==.Andarial:BAABLgAECn8YAAIKAAgJGQziJwA9AQAKAAgJGQziJwA9AQAAAA==.Andreth:BAAALgAECggJEwAAAA==.Anoxyn:BAAALgAECgcJBwAAAA==.Anthe:BAAALgAECgQJCAAAAA==.Anzul:BAABLgAECn8yAAMBAAkJVCCUJAByAgABAAkJQh+UJAByAgACAAUJxB0TGgBIAQAAAA==.',
Ar='Araestirra:BAABLgAECn8tAAMHAAcJHA80FwDpAAAIAAcJBgc5qwDsAAAHAAYJmRA0FwDpAAAAAA==.Arcanmaggy:BAAALgADCgkJHgABLgAFFAUJGgAIAHEEAA==.Ardahh:BAAALgADCgQJBAAAAA==.Arnold:BAABLgAECn8XAAMLAAgJ6hSYCwCjAQALAAgJ6hSYCwCjAQAMAAEJagPFOgEbAAABLgAECgkJGgAEAJwdAA==.Arntdorn:BAAALgADCgEJAQAAAA==.Arroes:BAABLgAECn8ZAAINAAgJGB/sFgBiAgANAAgJGB/sFgBiAgAAAA==.',
As='Asahna:BAAALgAECgQJBAAAAA==.',
At='Atlas:BAAALgAECggJCgABLgAECgkJGgAEAJwdAA==.',
Au='Aurrell:BAAALgADCgcJBwAAAA==.',
Av='Avoid:BAAALgAECgMJAwAAAA==.',
Ay='Ayroona:BAABLgAECn8pAAIOAAkJOgpQTgB4AQAOAAkJOgpQTgB4AQAAAA==.',
Az='Azhol:BAAALgAECgQJBAAAAA==.',
Ba='Bacontotem:BAAALgADCgMJBQAAAA==.Baelhal:BAACLgAFFH8ZAAIPAAQJmB1FFQBEAQAPAAQJmB1FFQBEAQAuAAQKfzQAAg8ACQmaHUMOACYCAA8ACQmaHUMOACYCAAAA.Balka:BAAALgADCgYJCAAAAA==.Barbaydos:BAAALgADCggJCQAAAA==.Barenjager:BAAALgAECgEJAQAAAA==.Basement:BAABLgAECn8bAAIMAAcJax4pMQABAgAMAAcJax4pMQABAgAAAA==.',
Be='Beastnite:BAAALgADCgkJKQABLgAECgkJGQAQAM4LAA==.Bellaburger:BAABLgAFFH8IAAIRAAQJsgYeIgDOAAARAAQJsgYeIgDOAAAAAA==.Bellissidan:BAAALgAECgEJAwAAAA==.Benedin:BAAALgAECgYJDwABLgAECgkJRgAJALYgAA==.',
Bi='Bigpapapete:BAAALgAECgYJAwAAAA==.Bigtex:BAABLgAECn81AAMGAAkJewuaAQASAQAGAAkJRwuaAQASAQASAAMJgwzIPAB/AAAAAA==.Biped:BAABLgAECn8zAAIJAAkJPhNaCADkAQAJAAkJPhNaCADkAQAAAA==.Birill:BAAALgAECgEJAgAAAA==.Bishul:BAAALgAECggJCQAAAA==.',
Bl='Blackdeath:BAACLgAFFH8FAAIQAAIJSgmI6wB+AAAQAAIJSgmI6wB+AAAuAAQKfykAAhAACAlwGHxhAKYBABAACAlwGHxhAKYBAAAA.',
Bo='Bombarian:BAAALgAECgUJCwAAAA==.Bone:BAAALgAECgEJAQAAAA==.Boomstique:BAABLgAECn83AAITAAkJZBzQAAAtAgATAAkJZBzQAAAtAgAAAA==.Boondocka:BAABLgAECn81AAITAAkJwBqGHAB6AgATAAkJwBqGHAB6AgAAAA==.',
Br='Brewco:BAACLgAFFH8PAAIUAAQJoRbhLQD9AAAUAAQJoRbhLQD9AAAuAAQKfzkABBQACQkEHKYUAJACABQACQkEHKYUAJACABUABgnDG1QSAJYBAAQABQl6Dw49ALIAAAAA.Brewer:BAAALgAECgEJAQAAAA==.Brickmebtch:BAAALgAECgEJAQAAAA==.Bruda:BAAALgAECgIJAwAAAA==.Brutalís:BAABLgAECn8oAAITAAkJFhIFPwDmAQATAAkJFhIFPwDmAQAAAA==.',
Bt='Btrain:BAABLgAECn8hAAMCAAYJ3AqaMQCfAAABAAYJzQZW9ADFAAACAAUJgAyaMQCfAAAAAA==.',
['Bó']='Bóunty:BAABLgAECn8bAAQDAAcJwx8mHwCjAQADAAcJrh0mHwCjAQATAAQJNx5HXgBNAQAWAAEJPgJtmAAeAAAAAA==.',
Ca='Camaryn:BAAALgADCgIJAgAAAA==.Canadia:BAAALgAECgQJBgAAAA==.Catdaddan:BAAALgADCgYJBgAAAA==.Cattnip:BAAALgAECgEJAQAAAA==.Cavisch:BAABLgAECn9GAAMJAAkJtiAcAQD/AgAJAAkJtiAcAQD/AgAIAAkJWBi5OwDsAQAAAA==.',
Ce='Cedric:BAAALgAECgEJAQABLgAECgYJBgAXAAAAAA==.Cenobité:BAABLgAECn8xAAIYAAkJKhhGAAC1AQAYAAkJKhhGAAC1AQAAAA==.Cerr:BAAALgAECgMJBAAAAA==.',
Ch='Chamber:BAAALgAECgYJCAABLgAECgcJGwAMAGseAA==.Chantilly:BAAALgADCgYJDwAAAA==.Chaosmaster:BAAALgAECgMJAwAAAA==.Chardee:BAABLgAFFH8HAAIZAAMJlBUmDQAVAQAZAAMJlBUmDQAVAQAAAA==.Charmeleon:BAABLgAECn8UAAMaAAgJCRJzQQAjAQAaAAgJCRJzQQAjAQAbAAIJfAwcNABWAAAAAA==.Charmin:BAAALgADCgUJBQAAAA==.Chiff:BAAALgADCgUJAwAAAA==.Chilledog:BAAALgADCgQJBAAAAA==.Chip:BAAALgAECgMJBgAAAA==.',
Ci='Cirax:BAABLgAECn8pAAITAAgJ6xUwPgDpAQATAAgJ6xUwPgDpAQAAAA==.Cirin:BAAALgADCgEJAQAAAA==.Citruscoolin:BAAALgAECgEJAQAAAA==.',
Cl='Cleetess:BAAALgAECgEJAQAAAA==.Clenton:BAABLgAECn9eAAMCAAkJpwymGABXAQACAAkJRgumGABXAQABAAgJCQhFrwAgAQAAAA==.Clipper:BAAALgADCgYJBgAAAA==.',
Co='Cobrakai:BAAALgAECgIJAgAAAA==.Cowboyup:BAAALgADCgYJBgAAAA==.',
Cr='Crichton:BAACLgAFFH8TAAIMAAQJ9RmHPgAtAQAMAAQJ9RmHPgAtAQAuAAQKfzIAAgwACQm0IYUMAOECAAwACQm0IYUMAOECAAAA.Cronnan:BAAALgAECgUJBQAAAA==.Crowford:BAABLgAECn8xAAITAAkJihLdTgC2AQATAAkJihLdTgC2AQAAAA==.',
Cy='Cyris:BAAALgAECgMJAwABLgAECgkJOwAcAJUFAA==.',
['Cá']='Cástle:BAAALgAECgEJAQABLgAECgcJGwAMAGseAA==.',
Da='Daemonfaust:BAAALgAECgYJDwAAAA==.Daevahna:BAAALgADCgYJBgAAAA==.Dahtty:BAAALgAECgYJBwAAAA==.Dak:BAABLgAECn8lAAIQAAkJWxe0MAA8AgAQAAkJWxe0MAA8AgABLgAECggJGwABAI0YAA==.Daksclaw:BAAALgAECgYJBgABLgAECggJGwABAI0YAA==.Daksmash:BAAALgAECgUJBQABLgAECggJGwABAI0YAA==.Dakstab:BAAALgADCgkJCQAAAA==.Dalsar:BAAALgAECggJDgAAAA==.Darkbrew:BAAALgADCgYJCAABLgAECgkJMwACAGwhAA==.Darkfes:BAAALgAECgEJAQAAAA==.Darkmiza:BAACLgAFFH8aAAIIAAUJcQR9bgDlAAAIAAUJcQR9bgDlAAAuAAQKfzsAAwgACAl1EVFlAHMBAAgACAl1EVFlAHMBAAcAAglDC0lYAGYAAAAA.Darkseer:BAAALgAFFAIJBAAAAA==.Darthbluto:BAAALgAECgUJDQABLgAECgYJDwAXAAAAAA==.Dasham:BAAALgAECgQJBAAAAA==.Daymann:BAABLgAECn8iAAIBAAkJHRa8SQDpAQABAAkJHRa8SQDpAQAAAA==.',
De='Deadazz:BAAALgADCgYJCgAAAA==.Deadmangalad:BAABLgAECn8rAAMYAAkJYwnfFQAqAQAYAAkJYwnfFQAqAQAPAAEJFATyaQAWAAAAAA==.Deathnotes:BAAALgADCgEJAQAAAA==.Deathquina:BAAALgAECgMJAwAAAA==.Deathtickle:BAAALgAECgcJAwAAAA==.Deedees:BAABLgAECn8eAAIdAAgJ5QZ3QwD/AAAdAAgJ5QZ3QwD/AAAAAA==.Demonbo:BAABLgAECn8aAAIMAAgJiBQUZABfAQAMAAgJiBQUZABfAQAAAA==.Demondrink:BAAALgAECgQJBgAAAA==.Demonhandler:BAAALgADCggJDwAAAA==.Deo:BAACLgAFFH8YAAMGAAQJGiDwEQB4AQAGAAQJGiDwEQB4AQAeAAMJMBTWKADKAAAuAAQKfz0AAwYACQkmJP8DACYDAAYACQkmJP8DACYDAB4AAgmSDeNjAFoAAAAA.Depression:BAAALgADCgUJBQAAAA==.Derpixion:BAABLgAECn8tAAMTAAgJYhlFJwAcAgATAAgJYhlFJwAcAgADAAUJYQtIPgDSAAAAAA==.Dessirius:BAAALgAECgEJAQAAAA==.Dethphalanax:BAAALgADCgUJCQAAAA==.',
Di='Dies:BAAALgAECgkJBAAAAA==.Digbie:BAAALgADCgYJBwAAAA==.Digs:BAAALgADCgMJAwAAAA==.Dirtnåp:BAAALgAECgUJDAAAAA==.Diskbänk:BAAALgAECgUJBwAAAA==.',
Dk='Dkho:BAACLgAFFH8FAAIfAAMJ7gOAkwCuAAAfAAMJ7gOAkwCuAAAuAAQKfxUAAh8ACAnCDbd/AHgBAB8ACAnCDbd/AHgBAAAA.',
Dr='Drago:BAAALgAECgEJBAAAAA==.Dragontoast:BAAALgAECggJDwAAAA==.Dral:BAEALgADCgkJKAAAAA==.Draygun:BAAALgAECgcJBwABLgAFFAQJGAAGABogAA==.Drphilyobody:BAABLgAECn8cAAIQAAcJCQhJsgARAQAQAAcJCQhJsgARAQAAAA==.Drui:BAABLgAECn8dAAIdAAgJsQ4dNgBkAQAdAAgJsQ4dNgBkAQAAAA==.Druidïan:BAAALgAECgQJBQAAAA==.',
Du='Duelittle:BAABLgAECn8mAAIgAAcJCgyNAgCxAAAgAAcJCgyNAgCxAAAAAA==.',
Dy='Dynwor:BAAALgAECgEJAgAAAA==.',
['Dé']='Dérailed:BAAALgAECgUJEgAAAA==.',
['Dî']='Dîz:BAAALgADCgEJAQAAAA==.',
Ea='Easme:BAABLgAECn8jAAMDAAkJughLHQCyAQADAAkJughLHQCyAQAWAAUJRANPYgC3AAAAAA==.Eatmyfrontal:BAABLgAECn86AAIfAAkJPxoCPwAgAgAfAAkJPxoCPwAgAgAAAA==.',
Eb='Ebbola:BAAALgADCgcJDgAAAA==.Ebon:BAAALgAECgMJAwABLgAECggJDAAXAAAAAA==.',
Eh='Ehsinat:BAAALgADCgYJBgAAAA==.',
El='Elaraa:BAAALgAECgYJBwAAAA==.Elaric:BAAALgAECgYJBgAAAA==.',
En='Engi:BAAALgAECgcJDAAAAA==.',
Ep='Epikrate:BAABLgAECn8eAAMIAAgJURl6QADbAQAIAAcJIRl6QADbAQAHAAMJ4hiqSACUAAAAAA==.',
Es='Escaper:BAABLgAECn84AAIYAAkJcxLOCwC7AQAYAAkJcxLOCwC7AQAAAA==.',
Ex='Extrema:BAAALgAECggJDwAAAA==.',
Ez='Ezsdruid:BAAALgAECgkJCQAAAA==.',
Fa='Faesha:BAAALgAECgEJAQAAAA==.Fallenash:BAAALgADCgMJAwABLgAFFAQJFgAfAGsfAA==.Fallenembers:BAACLgAFFH8WAAIfAAQJax8SRABhAQAfAAQJax8SRABhAQAuAAQKfzsAAh8ACQlJJb8GAEsDAB8ACQlJJb8GAEsDAAAA.Famine:BAABLgAECn8dAAMQAAgJ0AWfvAACAQAQAAgJwwSfvAACAQAYAAUJzAf7DADfAAAAAA==.Farquaadtwo:BAAALgAECgIJAgAAAA==.',
Fe='Fearofthdark:BAAALgADCgEJAQAAAA==.',
Ff='Fflar:BAAALgADCgUJBQABLgAECgkJAgAXAAAAAA==.',
Fh='Fhait:BAAALgAECgUJDQABLgAECgkJMwARACwLAA==.',
Fi='Firsttimepvp:BAACLgAFFH8HAAIZAAIJJg3yNQCJAAAZAAIJJg3yNQCJAAAuAAQKfx4AAhkACQnaE6gUAPwBABkACQnaE6gUAPwBAAAA.',
Fl='Flow:BAAALgADCgYJBgAAAA==.',
Fr='Frenchtoast:BAAALgAECgIJAgAAAA==.Frostyflaker:BAAALgAECgUJDAAAAA==.',
Ga='Gaiã:BAAALgADCgEJAgAAAA==.Galadan:BAAALgAECgUJDwABLgAECgkJKwAYAGMJAA==.Gaskelmarg:BAAALgAECgUJCwAAAA==.',
Gh='Ghosty:BAABLgAECn8hAAQhAAkJIRWVHwDRAQAhAAkJsRGVHwDRAQAiAAcJpAuKTgD+AAAgAAEJcAESnAAXAAAAAA==.Ghuun:BAAALgADCgEJAgABLgAFFAMJBwANAPELAA==.',
Gi='Gigaweed:BAABLgAFFH8HAAINAAMJ8Qt5RQCOAAANAAMJ8Qt5RQCOAAAAAA==.',
Go='Goblinlayer:BAAALgAECgYJEwAAAA==.Goldtusk:BAABLgAECn8iAAIVAAkJEBVaDgDQAQAVAAkJEBVaDgDQAQAAAA==.Gooey:BAAALgADCggJDgAAAA==.Gostann:BAABLgAECn8mAAIIAAkJlRclJwBAAgAIAAkJlRclJwBAAgAAAA==.',
Gr='Grayparser:BAAALgADCgYJCQAAAA==.Grimsly:BAAALgAECgEJAQAAAA==.Grundler:BAAALgAFFAEJAQAAAA==.Gryphone:BAAALgADCgkJEAAAAA==.',
Gu='Gurinendo:BAAALgAECgEJAgAAAA==.Gustwin:BAAALgAECgQJBgAAAA==.',
['Gà']='Gàins:BAAALgAECgMJAwABLgAECgkJMwACAGwhAA==.',
Ha='Hakmud:BAAALgADCgYJCwAAAA==.Halsin:BAAALgADCgMJAwABLgAECggJIAAjAEwYAA==.Hamshammy:BAAALgAECgEJAQAAAA==.',
He='Heftydin:BAAALgAECgMJCQAAAA==.Heftymists:BAAALgAECgUJBQAAAA==.Heftystomp:BAAALgADCgUJBQAAAA==.Heftyvoid:BAAALgADCgEJAQAAAA==.Hela:BAAALgADCgcJBwAAAA==.Hercyderc:BAAALgAECgEJAQABLgAFFAIJBQAMADYgAA==.Hettokal:BAAALgAECgQJBAAAAA==.Heyitsjimbo:BAAALgADCgUJCQAAAA==.',
Ho='Holierhtanu:BAAALgADCgQJBwAAAA==.Holyhellion:BAABLgAECn8dAAIMAAkJchECRQC4AQAMAAkJchECRQC4AQAAAA==.Hondojoe:BAACLgAFFH8YAAIiAAQJvx5nDwBbAQAiAAQJvx5nDwBbAQAuAAQKfzgAAyIACQnuIEoLAJsCACIACQnuIEoLAJsCACEAAgnYBvtuAE0AAAAA.Honeydrake:BAAALgAECgYJCAAAAA==.Hopewell:BAABLgAECn8yAAIFAAkJaAUSRgAnAQAFAAkJaAUSRgAnAQAAAA==.',
Hu='Huginn:BAAALgADCgEJAQAAAA==.Hugnsnuggle:BAABLgAECn8zAAILAAkJCAuBAAAoAQALAAkJCAuBAAAoAQABLgAECgkJMwARACwLAA==.Huhu:BAABLgAECn8ZAAIGAAkJrxRiKwCnAQAGAAkJrxRiKwCnAQAAAA==.Huma:BAAALgAECgYJEAABLgAFFAQJCgATAAAOAA==.Hundreg:BAAALgADCgYJBQAAAA==.',
Ib='Ibn:BAABLgAECn8sAAIeAAkJBws1HwBkAQAeAAkJBws1HwBkAQAAAA==.',
Ic='Icyhot:BAAALgAECgEJAgAAAA==.',
Id='Ideal:BAAALgADCgYJDAAAAA==.',
Il='Illaris:BAAALgADCgIJAgAAAA==.',
In='Infiniity:BAAALgAECgMJCQAAAA==.',
Ir='Irielle:BAAALgAECgUJDAAAAA==.',
Is='Ishanllin:BAAALgAECgIJAgAAAA==.',
Iv='Ivarurngamet:BAABLgAECn8iAAIMAAkJyRfaLgALAgAMAAkJyRfaLgALAgAAAA==.Ivylyn:BAAALgAECgUJBwAAAA==.',
Ix='Ixiyá:BAABLgAECn89AAMOAAkJNCNtBABxAwAOAAkJNCNtBABxAwAjAAEJzghSrgAqAAAAAA==.Ixií:BAAALgAECgEJAwAAAA==.Ixì:BAABLgAECn8XAAIUAAcJ1x32IQA4AgAUAAcJ1x32IQA4AgAAAA==.',
Ja='Jakeyprogue:BAAALgAFFAIJAwABLgAFFAIJBgAQAL4cAA==.Jakota:BAAALgADCgkJFAAAAA==.Jakskeleton:BAABLgAECn8fAAIPAAgJ2xoYEAAKAgAPAAgJ2xoYEAAKAgAAAA==.Jarobus:BAAALgAECgYJDgAAAA==.Jay:BAAALgADCgEJAQAAAA==.Jaynamir:BAAALgAECgYJEwAAAA==.Jayp:BAAALgAECgMJAwAAAA==.',
Jb='Jbernn:BAAALgAECgEJAQAAAA==.',
Je='Jeamica:BAAALgADCgcJCgAAAA==.',
Jo='Joemacho:BAAALgAECgcJDQABLgAFFAQJGAAiAL8eAA==.Joshtee:BAAALgAECgMJBQAAAA==.Joslyn:BAAALgAECgQJBQAAAA==.Jourdan:BAAALgADCgcJDQAAAA==.',
Ju='Judax:BAACLgAFFH8HAAIjAAMJaQ8GNwCyAAAjAAMJaQ8GNwCyAAAuAAQKfz0AAiMACQm0GyYTAFUCACMACQm0GyYTAFUCAAAA.Justagirl:BAABLgAECn8zAAIRAAkJLAvqMwA0AQARAAkJLAvqMwA0AQAAAA==.Justiceboyd:BAAALgADCgMJAwAAAA==.Juti:BAAALgAECgMJBgAAAA==.',
Jy='Jymion:BAAALgADCgEJAQAAAA==.',
Ka='Kadooka:BAABLgAECn8hAAITAAgJFxfHTwCzAQATAAgJFxfHTwCzAQAAAA==.Kahlyn:BAAALgAECgYJCwAAAA==.Kajax:BAABLgAECn8qAAIZAAgJISMwCAANAwAZAAgJISMwCAANAwAAAA==.Kaldaran:BAABLgAECn8UAAMPAAgJQhrHGwB+AQAPAAgJQhrHGwB+AQAQAAIJtQTkUwFOAAAAAA==.Kalleigh:BAAALgADCgQJBAABLgAECgkJOwAcAJUFAA==.Karen:BAAALgADCgcJHAAAAA==.Karne:BAAALgADCgYJBgAAAA==.Katira:BAAALgAECgEJAQAAAA==.Kazarath:BAAALgADCgUJBQAAAA==.',
Ke='Keeganw:BAABLgAECn8cAAIPAAYJzxqQJgAfAQAPAAYJzxqQJgAfAQAAAA==.Keelay:BAABLgAECn9CAAIFAAkJxR5pCgDlAgAFAAkJxR5pCgDlAgAAAA==.',
Kh='Kheegorn:BAABLgAECn8bAAIBAAgJjRhqTwDzAQABAAgJjRhqTwDzAQAAAA==.Khyla:BAAALgAECgEJAQAAAA==.',
Ki='Killua:BAAALgADCgYJBgABLgADCgcJCwAXAAAAAA==.Kimiko:BAAALgAECgcJCwAAAA==.',
Kl='Klaw:BAAALgAECgQJBAABLgAECggJKgAZACEjAA==.',
Ko='Koffcmorbius:BAAALgAECgMJAwAAAA==.Koriban:BAABLgAECn8lAAIfAAkJaA68aQCoAQAfAAkJaA68aQCoAQAAAA==.Korreban:BAAALgAECgYJBgABLgAECgkJJQAfAGgOAA==.',
Kr='Kra:BAAALgAECgEJAgABLgAFFAMJBwANAPELAA==.Kraken:BAACLgAFFH8FAAIHAAMJ0Q2vDQDIAAAHAAMJ0Q2vDQDIAAAuAAQKfysAAgcACQlzIvIAAAUDAAcACQlzIvIAAAUDAAEuAAUUAwkHAA0A8QsA.Krim:BAAALgADCgYJBgAAAA==.',
Ku='Kubb:BAABLgAECn87AAIcAAkJlQW+AAATAQAcAAkJlQW+AAATAQAAAA==.Kunst:BAAALgADCgEJAQAAAA==.',
Kw='Kweh:BAACLgAFFH8ZAAIVAAYJlh+rAQDcAQAVAAYJlh+rAQDcAQAuAAQKfy0AAxUACQk6IxoFAMACABUACQk6IxoFAMACAB0ABQkbDqFGAPEAAAAA.',
['Kê']='Kêlsen:BAAALgAECgUJBwAAAA==.',
La='Lachupacabra:BAAALgAECgEJAQAAAA==.Larrissa:BAABLgAECn8nAAMJAAkJyAbaEwAyAQAJAAkJyAbaEwAyAQAHAAEJggPhewAlAAAAAA==.Larry:BAABLgAFFH8SAAIMAAYJghRvPgAtAQAMAAYJghRvPgAtAQAAAA==.Laurlynn:BAAALgAECggJEQAAAA==.Lavina:BAAALgADCgUJBQAAAA==.',
Le='Lenwe:BAAALgAECgYJCgABLgAECgcJLQAiAGwOAA==.Lettuceprey:BAABLgAECn8tAAIiAAkJtQ7NKgBxAQAiAAkJtQ7NKgBxAQAAAA==.',
Li='Lierise:BAAALgAECggJEwAAAA==.Lies:BAAALgADCgkJCQAAAA==.Lightsnipe:BAAALgAECgQJBAAAAA==.Lilkelp:BAAALgAECgYJBwAAAA==.Lilspazz:BAAALgADCgMJAwAAAA==.Lithiri:BAAALgAECgUJBgABLgAECggJHgAQAK0fAA==.',
Lo='Lockatute:BAAALgAECggJDwAAAA==.Lockdeath:BAAALgAECgQJCQAAAA==.Loric:BAAALgADCgkJCQAAAA==.Loxia:BAABLgAECn8UAAIHAAgJ8wpyEwAWAQAHAAgJ8wpyEwAWAQAAAA==.',
Lu='Lucille:BAACLgAFFH8FAAIfAAEJfAZbGABGAAAfAAEJfAZbGABGAAAuAAQKfx8AAh8ACAnjEWoDABwBAB8ACAnjEWoDABwBAAAA.Lucrotia:BAAALgADCgQJBAAAAA==.Luukmosh:BAAALgAECgUJCQAAAA==.',
Ma='Maavarra:BAABLgAECn8jAAMVAAkJAxnGCgATAgAVAAkJAxnGCgATAgAUAAEJGwa46AAjAAAAAA==.Madilyons:BAAALgADCgIJAgAAAA==.Madischa:BAAALgAECgcJDQAAAA==.Magicdance:BAACLgAFFH8JAAIjAAQJxQJpOACtAAAjAAQJxQJpOACtAAAuAAQKfzIAAw4ACQkoEUJLAIMBAA4ACAl7EUJLAIMBACMACQnSCaRAADIBAAAA.Magolthel:BAAALgADCgYJCQAAAA==.Maimgame:BAABLgAECn8WAAIVAAgJchK/CwACAgAVAAgJchK/CwACAgAAAA==.Majicbob:BAABLgAECn8gAAIjAAgJTBgUHgDxAQAjAAgJTBgUHgDxAQAAAA==.Maki:BAAALgAECggJEwAAAA==.Mansion:BAAALgADCgQJBgABLgAECgcJGwAMAGseAA==.Marilune:BAAALgADCggJCQAAAA==.Marn:BAAALgADCgQJBAAAAA==.Marthran:BAAALgADCgIJAgAAAA==.Maxlin:BAAALgAECgEJAgAAAA==.',
Mc='Mctowlie:BAAALgAECgYJCAAAAA==.',
Me='Mehänemäntä:BAAALgAECggJDwAAAA==.Meldo:BAAALgADCggJDQAAAA==.Mellinessa:BAABLgAECn8aAAMYAAcJqBXKEwBAAQAQAAYJJRKQlABXAQAYAAUJWBXKEwBAAQAAAA==.Mena:BAAALgADCgUJBgAAAA==.Merixa:BAAALgADCgEJAQAAAA==.',
Mf='Mfdkidney:BAAALgAECgIJAgAAAA==.',
Mi='Midou:BAAALgAECgMJAwABLgAFFAQJCQAjAMUCAA==.Minthraxis:BAAALgADCgEJAQAAAA==.Misaun:BAAALgAECgEJAQAAAA==.Misericorde:BAACLgAFFH8QAAIRAAQJUyTRCACNAQARAAQJUyTRCACNAQAuAAQKfzwAAhEACQkYJqUBAF0DABEACQkYJqUBAF0DAAAA.Misstreater:BAABLgAECn8fAAMkAAgJdgYjCgDpAAAfAAcJZAUgzgD0AAAkAAcJyQYjCgDpAAAAAA==.',
Mo='Momentomori:BAABLgAECn8gAAIIAAkJvghlbwBcAQAIAAkJvghlbwBcAQAAAA==.Monbow:BAAALgAECgMJBwABLgAECggJGgAMAIgUAA==.Monocerotis:BAAALgAECgQJBAAAAA==.Morishima:BAACLgAFFH8XAAIZAAQJ6xmvFgBYAQAZAAQJ6xmvFgBYAQAuAAQKf0YAAxkACQlkJPcCACIDABkACQlkJPcCACIDACUAAQkJFtglAD0AAAAA.Morthis:BAABLgAECn8uAAMWAAkJeQppEgA2AQAWAAkJeQppEgA2AQADAAMJWgM3WABMAAAAAA==.',
Mu='Multipàss:BAAALgADCgcJCgAAAA==.',
My='Mydarling:BAAALgAFFAIJAwAAAA==.Mymoon:BAAALgAECgIJAgAAAA==.Myris:BAACLgAFFH8FAAIQAAMJtw8MqADMAAAQAAMJtw8MqADMAAAuAAQKfywAAhAACQmpG28nAGUCABAACQmpG28nAGUCAAAA.',
Na='Narcan:BAAALgAECgUJDQAAAA==.Naturalchi:BAABLgAECn8wAAMRAAkJByWbAgBCAwARAAkJiiSbAgBCAwAmAAgJ8x5yDABuAgAAAA==.',
Nb='Nbi:BAAALgAECgEJAQAAAA==.',
Ne='Nefilion:BAABLgAFFH8GAAIQAAIJ7wsL6QB/AAAQAAIJ7wsL6QB/AAAAAA==.Nemas:BAABLgAECn8hAAICAAgJrxnuDgDVAQACAAgJrxnuDgDVAQAAAA==.Neverleft:BAAALgAECgUJCAAAAA==.Nezin:BAABLgAECn8sAAQaAAkJURZjAADCAQAaAAkJDxVjAADCAQAnAAYJJRNDDwAXAQAbAAIJuQ2jQABlAAAAAA==.',
Ni='Nightrun:BAAALgADCgcJCwAAAA==.Nightrunnêr:BAAALgAECgUJCwABLgAECgkJMwACAGwhAA==.Nineadin:BAACLgAFFH8PAAMBAAQJnwsbWAAAAQABAAQJnwsbWAAAAQAFAAMJ2RaMMACzAAAuAAQKfycAAwUACQmYHU0TAHgCAAUACQmYHU0TAHgCAAEAAgkjHZkIAa4AAAAA.Nineshots:BAAALgAFFAMJBAABLgAFFAQJDwABAJ8LAA==.Ninetoads:BAAALgAECgcJDQABLgAFFAQJDwABAJ8LAA==.Nirvanas:BAABLgAECn8cAAIVAAgJngtyHQAeAQAVAAgJngtyHQAeAQAAAA==.Niyoko:BAAALgADCgcJBwAAAA==.',
No='Nomik:BAABLgAECn8tAAMiAAcJbA6ENwAgAQAiAAcJbA6ENwAgAQAgAAYJ1QewYwCMAAAAAA==.Nonah:BAAALgADCgEJAgAAAA==.North:BAAALgAECggJCAAAAA==.',
Nu='Nuke:BAABLgAECn8VAAITAAQJvBkqBAD9AAATAAQJvBkqBAD9AAAAAA==.Nullspace:BAABLgAECn8pAAMiAAkJXhq+FAAvAgAiAAkJXhq+FAAvAgAgAAMJAQz+AgCWAAAAAA==.Nunskee:BAAALgAECgQJBAAAAA==.',
['Ní']='Níght:BAABLgAECn85AAIEAAgJKRdYFQCqAQAEAAgJKRdYFQCqAQAAAA==.',
Oa='Oaken:BAAALgADCgkJCgAAAA==.',
Oc='Occultivated:BAAALgAECgQJBgAAAA==.',
Oh='Ohhk:BAAALgAECgMJAwAAAA==.',
Om='Ommû:BAAALgAECgMJCAAAAA==.',
Op='Op:BAAALgAECgIJAgABLgAFFAMJBwANAPELAA==.',
Or='Orillar:BAAALgADCgEJAQAAAA==.',
Pa='Pakeydk:BAABLgAFFH8GAAIQAAIJvhxZxgCfAAAQAAIJvhxZxgCfAAAAAA==.Palacia:BAAALgAECggJEQAAAA==.Pancakedealr:BAAALgAECgUJEAAAAA==.Pancakeeater:BAAALgAECgUJCgAAAA==.',
Pe='Peaches:BAAALgAECgEJAQAAAA==.Peerow:BAAALgADCgMJAwAAAA==.Permelia:BAAALgADCgYJBgAAAA==.Petrichorica:BAAALgAECgcJEQAAAA==.Peí:BAAALgAECgEJAQAAAA==.',
Ph='Phatjake:BAAALgADCgYJBgAAAA==.',
Pi='Ping:BAABLgAFFH8GAAINAAYJ7xQ5AQD3AQANAAYJ7xQ5AQD3AQAAAA==.Pintobeans:BAABLgAECn8XAAITAAkJlQVMdwBRAQATAAkJlQVMdwBRAQAAAA==.',
Pl='Plutonix:BAAALgAECgMJBQAAAA==.',
Pr='Preachêr:BAAALgAECgQJCQABLgAECgkJMwACAGwhAA==.Prohteus:BAAALgAECgEJAQABLgAECgMJBQAXAAAAAA==.',
Pu='Puuhceew:BAABLgAECn8eAAIiAAcJtA6wNgAlAQAiAAcJtA6wNgAlAQAAAA==.',
Qu='Quan:BAEALgADCgcJCQABLgADCgkJKAAXAAAAAA==.Quelaag:BAAALgADCgQJBAAAAA==.Quenthel:BAAALgAECgkJAgAAAA==.Quiescent:BAABLgAECn8pAAIMAAgJdRr5KQAiAgAMAAgJdRr5KQAiAgAAAA==.Quina:BAAALgAECgQJBAAAAA==.',
Ra='Ragingtides:BAAALgADCgEJAQAAAA==.Rainera:BAABLgAECn8uAAMJAAkJfSS8AQDWAgAJAAkJfSS8AQDWAgAIAAEJAxH2OgE1AAABLgAFFAYJFgALAHgkAA==.Ramanas:BAABLgAECn8YAAMgAAgJDhHLLwBgAQAgAAcJjRLLLwBgAQAhAAYJnBGILQAxAQAAAA==.Ramrod:BAAALgAECgIJAwAAAA==.Randomizwe:BAABLgAECn8uAAIBAAkJtB5EIwB4AgABAAkJtB5EIwB4AgAAAA==.Raspet:BAAALgADCgIJAgAAAA==.Rattles:BAAALgADCgcJCwAAAA==.Raynu:BAAALgAECgEJAwAAAA==.Raín:BAAALgAECggJDwAAAA==.',
Re='Relearning:BAABLgAECn8tAAIIAAkJJg1LUgClAQAIAAkJJg1LUgClAQAAAA==.Relyn:BAAALgAECggJDwAAAA==.Resurgencê:BAABLgAECn8zAAICAAkJbCEaAAClAgACAAkJbCEaAAClAgAAAA==.Retalltheway:BAAALgADCgEJAQAAAA==.',
Ri='Riggler:BAAALgAECgcJBwAAAA==.Riordan:BAABLgAECn8lAAMBAAgJ6BQ0kgBOAQABAAcJChQ0kgBOAQACAAQJ9xPgJQDnAAAAAA==.',
Ro='Rohz:BAAALgADCgIJAgABLgAECgcJGwAMAGseAA==.Rojeton:BAAALgADCgUJBwAAAA==.Rosenth:BAAALgADCggJEwAAAA==.Rotandroll:BAAALgAECgcJDwAAAA==.Rothema:BAABLgAECn8hAAMOAAkJEwfmkwCvAAAOAAcJdAPmkwCvAAAjAAgJkwhTAwCFAAAAAA==.Routh:BAAALgAECgEJAQAAAA==.',
Rw='Rwlmaster:BAABLgAECn89AAIPAAkJSBuvDwAQAgAPAAkJSBuvDwAQAgAAAA==.',
Ry='Rynzia:BAACLgAFFH8ZAAMnAAQJMhkkBAAtAQAaAAQJMhmeJwAuAQAnAAQJMxMkBAAtAQAuAAQKf0cABCcACQngIa0BANECACcACQktH60BANECABoACQnJIGEMAJUCABsABwnnEroSAJ0BAAAA.',
Sa='Sadabacus:BAAALgAECgEJAgAAAA==.Sagittarian:BAAALgADCgUJBwAAAA==.Sandwiches:BAAALgAECggJDgAAAA==.Santose:BAAALgAECgIJAgAAAA==.Sarya:BAAALgAECgQJBAABLgAECgkJAgAXAAAAAA==.',
Sc='Scalyt:BAAALgADCgYJBgAAAA==.Scerra:BAABLgAECn8mAAIQAAkJExBiTgDXAQAQAAkJExBiTgDXAQAAAA==.Schmerz:BAAALgADCgUJBQAAAA==.Scridderz:BAAALgAECgMJBgAAAA==.',
Se='Sendia:BAAALgADCgQJBAABLgAECgkJSwADACogAA==.Sephiros:BAAALgADCgIJAgAAAA==.Seru:BAAALgAECggJDwAAAA==.Seta:BAABLgAECn8bAAIMAAgJ3xNeQwDmAQAMAAgJ3xNeQwDmAQAAAA==.Seviran:BAAALgADCgIJAwAAAA==.',
Sh='Shakeyjams:BAAALgADCgYJBgABLgAFFAIJBgAQAL4cAA==.Shamantha:BAAALgADCgEJAQAAAA==.Shamarha:BAABLgAECn8cAAIOAAgJaBoIMwDnAQAOAAgJaBoIMwDnAQAAAA==.Shaolin:BAAALgAECgQJBAAAAA==.Sharriavolf:BAABLgAECn9FAAQIAAkJxCMDAgAbAQAHAAQJ+CMLIABSAQAIAAcJ7CEDAgAbAQAJAAEJAAB7IwBkAAAAAA==.Shato:BAAALgAECgYJCQAAAA==.Sheoth:BAAALgADCgQJBAAAAA==.Shiori:BAAALgAECgcJEAAAAA==.Shortmedic:BAAALgAECgQJBAAAAA==.Shotzys:BAAALgAECgYJEAAAAA==.Shrieve:BAAALgAECgMJAwAAAA==.Shurg:BAAALgAECgQJBAAAAA==.',
Si='Sicarius:BAAALgADCgcJCgABLgAECgEJAQAXAAAAAA==.Siggismund:BAABLgAECn8rAAIBAAkJKguZeAB9AQABAAkJKguZeAB9AQAAAA==.Simichaelton:BAACLgAFFH8MAAIfAAUJCBBLYQAfAQAfAAUJCBBLYQAfAQAuAAQKfxoAAh8ACQnDFFlJAP8BAB8ACQnDFFlJAP8BAAAA.Sinpal:BAABLgAFFH8IAAIBAAMJTxlcYQDsAAABAAMJTxlcYQDsAAABLgAFFAQJDQAIABIcAA==.Sinthea:BAAALgAECgkJAQAAAA==.Sioce:BAAALgADCgkJKgAAAA==.',
Sk='Skrobifu:BAAALgADCgQJAwAAAA==.',
Sl='Slickacitic:BAAALgAECgYJBwABLgAECgcJHwAOAAwLAA==.Slimselect:BAAALgADCgMJAwAAAA==.Slimt:BAAALgADCgMJAwAAAA==.Sloppyshids:BAAALgAECgcJCAAAAA==.',
Sm='Smorroy:BAAALgADCgYJBgAAAA==.',
So='Softbakedhoj:BAABLgAECn8eAAIBAAgJ/BxdSQAGAgABAAgJ/BxdSQAGAgAAAA==.Sophrosyne:BAABLgAECn8sAAITAAkJhxvhLwAdAgATAAkJhxvhLwAdAgAAAA==.Souless:BAAALgAECgYJBgAAAA==.',
Sp='Sparkness:BAAALgAECgMJAwAAAA==.Spartaaxd:BAABLgAECn8uAAIYAAkJkRCfAAAHAQAYAAkJkRCfAAAHAQAAAA==.Spookems:BAAALgAECgIJAgABLgAFFAMJAwAXAAAAAA==.Spycy:BAABLgAECn8UAAIfAAkJ3BA2hQBtAQAfAAkJ3BA2hQBtAQAAAA==.',
St='Stagerrind:BAAALgAECgUJDQAAAA==.Starfall:BAAALgAECgkJAgAAAA==.Steiner:BAABLgAECn8qAAMFAAkJOwzgNAB+AQAFAAkJOwzgNAB+AQABAAEJ9Qf+tQEnAAAAAA==.Stinkyfrog:BAACLgAFFH8GAAIBAAMJxQzyhgClAAABAAMJxQzyhgClAAAuAAQKfyMAAgEACQk+It4LAAYDAAEACQk+It4LAAYDAAAA.Stovetop:BAAALgAECgEJAQABLgAECgUJBwAXAAAAAA==.Stubmcbean:BAAALgADCggJCQABLgAECgkJOwAcAJUFAA==.Stunted:BAAALgAECgMJAwAAAA==.',
Su='Sugarfrost:BAABLgAECn8mAAIfAAkJOgs2pAA0AQAfAAkJOgs2pAA0AQAAAA==.Sugarseer:BAAALgAECgQJBAABLgAECgkJJgAfADoLAA==.Suka:BAAALgAECgUJEAAAAA==.Surok:BAAALgAECgYJDwAAAA==.',
Sw='Sweetleaf:BAAALgAECgUJCAAAAA==.Swiftleaf:BAAALgAECgcJDAAAAA==.',
Sy='Sylentcurse:BAABLgAECn8hAAIJAAgJDQuvEQBKAQAJAAgJDQuvEQBKAQABLgAECgkJKAATABYSAA==.Sylentstorm:BAABLgAECn8ZAAMOAAgJBAPFgwDXAAAOAAgJBAPFgwDXAAAjAAEJAAAFyQAAAAABLgAECgkJKAATABYSAA==.Syleta:BAABLgAECn9LAAQDAAkJKiCaBADjAgADAAkJ3h+aBADjAgATAAcJwxwNMADwAQAWAAYJCRNpRABEAQAAAA==.',
Ta='Tabraxis:BAAALgAECgEJAQAAAA==.Tagalorc:BAABLgAECn8fAAMkAAkJPRVFAwD2AQAkAAkJPRVFAwD2AQAfAAEJ8QGfgQEcAAAAAA==.Takamaki:BAAALgAECgEJAwAAAA==.Tanksbacon:BAABLgAECn8oAAMBAAkJgBnNMAA9AgABAAkJgBnNMAA9AgACAAQJtxKSLwCWAAAAAA==.Taylith:BAAALgAECgYJEgAAAA==.',
Te='Teana:BAABLgAECn8iAAIYAAgJ5A+UEABtAQAYAAgJ5A+UEABtAQAAAA==.Teannev:BAAALgADCgYJBgAAAA==.Tempestas:BAAALgAECgEJAQAAAA==.',
Th='Tharos:BAAALgAECgUJCgAAAA==.Thebrewco:BAAALgADCgMJAwABLgAFFAQJDwAUAKEWAA==.Thechadd:BAABLgAFFH8HAAIjAAcJaAPiNwCvAAAjAAcJaAPiNwCvAAAAAA==.Thelegendáry:BAACLgAFFH8OAAIOAAQJlhE4PADyAAAOAAQJlhE4PADyAAAuAAQKfxoAAg4ABgmWF0FKAFkBAA4ABgmWF0FKAFkBAAAA.Thetool:BAAALgAECgMJBAAAAA==.Thraine:BAAALgAECgYJCwAAAA==.',
Ti='Tinyshadowz:BAAALgAECgEJAQAAAA==.Tione:BAABLgAECn85AAMdAAkJJRz9EgA9AgAdAAgJMh39EgA9AgAUAAkJFQubVAA+AQAAAA==.Tireck:BAAALgADCgIJAgAAAA==.',
To='Toriee:BAAALgAECgkJCQAAAA==.Tormented:BAAALgAECgMJAwAAAA==.Totembish:BAABLgAECn8gAAIjAAkJZAnXPABCAQAjAAkJZAnXPABCAQAAAA==.',
Tr='Treebear:BAAALgADCgcJDQAAAA==.Tremor:BAAALgADCgIJAgAAAA==.Trisstan:BAABLgAECn8rAAMfAAkJRgpjkgBTAQAfAAkJRgpjkgBTAQAoAAMJawEvDQBVAAAAAA==.Trucknly:BAAALgADCgMJAwAAAA==.',
Tu='Tundarian:BAAALgAECggJDwAAAA==.Tundie:BAAALgAFFAEJAQAAAA==.',
Tw='Twigz:BAAALgADCgcJBgAAAA==.',
Ty='Tyronicals:BAABLgAECn8iAAMfAAkJshvvOwAqAgAfAAkJkBjvOwAqAgAkAAUJHyAJBgDAAQAAAA==.Tyster:BAACLgAFFH8QAAIBAAQJqhNkBQDyAAABAAQJqhNkBQDyAAAuAAQKfyMAAwEACQl0FSJEAPoBAAEACQnGFCJEAPoBAAIAAQkbFgNKAEEAAAAA.',
['Tø']='Tørmëntëd:BAAALgAECgMJBAAAAA==.',
Ug='Ugotdusted:BAAALgADCgYJBgAAAA==.',
Uk='Ukyo:BAAALgADCgUJBgAAAA==.',
Ul='Ullidon:BAAALgAECgIJAgAAAA==.',
Um='Umbrã:BAAALgADCgEJAQAAAA==.',
Un='Unavoidably:BAAALgADCgIJAgAAAA==.Undol:BAAALgADCggJGwABLgAECgkJOwAcAJUFAA==.',
Ux='Uxe:BAAALgAFFAEJAQABLgAECgkJJAAmAFkaAA==.',
Uz='Uzu:BAABLgAECn8kAAMmAAkJWRqcJQCBAQAmAAkJWRqcJQCBAQARAAEJyhLUjQBDAAAAAA==.',
Va='Valios:BAAALgADCgcJBwAAAA==.Valorr:BAAALgAECgQJBAAAAA==.Vamp:BAABLgAECn8YAAIOAAgJxxbxLwDIAQAOAAgJxxbxLwDIAQAAAA==.Vandaldor:BAAALgAECgYJEQAAAA==.Vandrana:BAAALgAECgUJBQAAAA==.Vasalrius:BAAALgADCgIJAgAAAA==.Vasilli:BAAALgADCgYJDwAAAA==.',
Ve='Vedrix:BAAALgAECgcJBgAAAA==.Vellora:BAAALgADCgUJBQAAAA==.Veloth:BAACLgAFFH8aAAIfAAQJYhkfUAA9AQAfAAQJYhkfUAA9AQAuAAQKfy8AAh8ACQlDIiEiAJUCAB8ACQlDIiEiAJUCAAAA.Vexnyx:BAAALgADCgcJCAAAAA==.',
Vh='Vhitahni:BAAALgAECgMJAwAAAA==.',
Vi='Viggle:BAAALgADCggJCAABLgAECgkJMwACAGwhAA==.Vireaux:BAAALgADCgEJAQAAAA==.Viviro:BAAALgADCgcJDQAAAA==.',
Vl='Vll:BAABLgAECn8nAAMTAAkJtRsMKQA6AgATAAkJtRsMKQA6AgADAAIJewTpKgBVAAAAAA==.',
Vo='Voodoomike:BAAALgAECgIJAgAAAA==.',
Vy='Vynlorin:BAAALgAECgYJBgABLgAECgkJMgABAFQgAA==.',
Wa='Wanawa:BAAALgAECgMJAwABLgAECgkJIgAVABAVAA==.Wanghaf:BAAALgAECgYJDQAAAA==.Warhorne:BAAALgAECgEJAQABLgAECgkJIgAVABAVAA==.Warthog:BAAALgADCgkJFQAAAA==.Waterbender:BAABLgAECn8ZAAIOAAkJRRqOGQB+AgAOAAkJRRqOGQB+AgAAAA==.',
We='Weechuup:BAAALgADCggJEAAAAA==.Weleindon:BAAALgADCgMJAwAAAA==.',
Wi='Wifeotusk:BAAALgAECgkJEAAAAA==.Wiggle:BAAALgADCgMJAwAAAA==.Willmar:BAABLgAECn8hAAIBAAgJ2hY7UQDVAQABAAgJ2hY7UQDVAQAAAA==.Wilshaman:BAAALgAECgUJBgAAAA==.Window:BAAALgADCgUJBQABLgAECgcJGwAMAGseAA==.',
Wm='Wmdplague:BAAALgADCgYJBgAAAA==.',
Wo='Wolf:BAABLgAECn8oAAIEAAkJNhc4EwDAAQAEAAkJNhc4EwDAAQAAAA==.Wolfton:BAAALgAECgMJAwAAAA==.Woodtique:BAAALgAECgMJBgAAAA==.',
Wr='Wrekkit:BAAALgAECggJDgAAAA==.',
Wy='Wylian:BAAALgAECgIJAgAAAA==.',
Xa='Xaeri:BAAALgADCgMJBAAAAA==.Xameris:BAAALgADCgEJAQAAAA==.Xandercruise:BAABLgAECn8UAAMTAAgJIhvAHQBTAgATAAgJIhvAHQBTAgAWAAMJrAJgdABtAAAAAA==.',
Xe='Xelgoth:BAAALgADCgcJBgAAAA==.Xelphie:BAAALgADCgUJBQAAAA==.',
Xu='Xuchilbara:BAABLgAECn8eAAIVAAgJuRoiCwALAgAVAAgJuRoiCwALAgAAAA==.',
Xy='Xyro:BAAALgAECgUJBQABLgAECggJGwABAI0YAA==.',
Ya='Yamato:BAAALgAECgcJDQAAAA==.',
Za='Zaledron:BAABLgAECn8eAAIQAAgJrR/ENQAoAgAQAAgJrR/ENQAoAgAAAA==.Zapnasty:BAAALgADCgcJBgAAAA==.',
Ze='Zenno:BAABLgAECn8qAAMcAAkJXxIVAQDUAAAcAAkJXxIVAQDUAAAOAAMJVgh7tgBeAAAAAA==.Zevorcia:BAAALgAECgMJAwAAAA==.',
Zh='Zhades:BAACLgAFFH8gAAMQAAUJXB10BABSAQAQAAUJXB10BABSAQAYAAMJhxRrFADpAAAuAAQKf0YAAxAACQmiJY8HADkDABAACQmiJY8HADkDABgACAlQIf0DAJcCAAAA.Zhandaria:BAAALgAECgQJBwAAAA==.Zhort:BAAALgAECgIJAwAAAA==.Zhulodok:BAAALgADCgMJAwAAAA==.',
Zi='Zioki:BAAALgADCgcJEgABLgAECgEJAQAXAAAAAA==.',
Zo='Zodgul:BAAALgAECgQJBAAAAA==.Zomby:BAABLgAFFH8IAAIQAAMJXA6OpwDMAAAQAAMJXA6OpwDMAAABLgAFFAUJDAAfAAgQAA==.',
Zp='Zpersephone:BAABLgAECn8cAAIIAAcJDxMiaQBqAQAIAAcJDxMiaQBqAQABLgAFFAUJIAAQAFwdAA==.',
Zr='Zrii:BAAALgAECggJCgAAAA==.',
Zu='Zultan:BAACLgAFFH8RAAIIAAQJawcFaQDzAAAIAAQJawcFaQDzAAAuAAQKfzsAAwgACQmLGQsgAGUCAAgACQmLGQsgAGUCAAcAAglmBBtIABkAAAAA.Zurrik:BAACLgAFFH8LAAMdAAQJTwYUMQC+AAAdAAQJEgQUMQC+AAAEAAMJYQZ9KgBxAAAuAAQKfz4AAx0ACQm0EuQgAMIBAB0ACQnwEeQgAMIBAAQAAgn+E0BNAHcAAAAA.',
Zy='Zynofhealth:BAAALgADCgUJAwAAAA==.',
['Çõ']='Çõîñflïp:BAAALgADCgcJHAAAAA==.',
['Ðr']='Ðream:BAACLgAFFH8GAAImAAMJqBTYEgDjAAAmAAMJqBTYEgDjAAAuAAQKfycAAyYACAmEHzsJAPUCACYACAmEHzsJAPUCABEAAwkjGQ+ZADYAAAAA.',
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
