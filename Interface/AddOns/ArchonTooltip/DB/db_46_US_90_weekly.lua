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

local lookup = {'Rogue-Subtlety','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Balance','Druid-Restoration','Evoker-Augmentation','Mage-Frost','Shaman-Elemental','Warrior-Arms','Warrior-Fury','Warrior-Protection','Monk-Windwalker','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Shadow','Priest-Holy','Unknown-Unknown','DeathKnight-Unholy','Paladin-Retribution','DemonHunter-Havoc','Shaman-Restoration','Rogue-Outlaw','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Devastation','Evoker-Preservation','DeathKnight-Blood','Druid-Guardian','Monk-Mistweaver','Shaman-Enhancement','Priest-Discipline','Mage-Fire','Mage-Arcane','Druid-Feral','DeathKnight-Frost','Rogue-Assassination','Paladin-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aamon:BAAALgAECgQJCgAAAA==.',
Ab='Abacus:BAABLgAECn8jAAIBAAkJjyK+CwBoAgABAAkJjyK+CwBoAgAAAA==.',
Ac='Acin:BAAALgADCgQJBAAAAA==.',
Ad='Adam:BAACLgAFFH8cAAQCAAgJfxvsJwCpAQACAAYJNxzsJwCpAQADAAMJlBFcDQCiAAAEAAEJECarEwBvAAAuAAQKfy4ABAIACQk2JF4WAM4CAAIACQmcI14WAM4CAAMABQljJKcNAOsBAAQAAQkaI5QvAGAAAAAA.Adedruid:BAABLgAECn8gAAMFAAYJdR9cKwCnAQAFAAYJdR9cKwCnAQAGAAYJ3xoBSgB6AQAAAA==.Adevoker:BAAALgAECgQJBAAAAA==.Adragon:BAABLgAECn8rAAIHAAkJ5RpNDwByAgAHAAkJ5RpNDwByAgAAAA==.',
Ae='Aengyl:BAAALgAECgQJBAAAAA==.Aeonne:BAABLgAECn8WAAIIAAgJyxLYkQBUAQAIAAgJyxLYkQBUAQAAAA==.',
Ak='Akshul:BAABLgAECn8UAAIJAAYJ5Q1HRgAvAQAJAAYJ5Q1HRgAvAQAAAA==.Akurama:BAAALgAECgcJCgAAAA==.',
Al='Alannon:BAAALgADCgUJBQAAAA==.Aldrea:BAAALgAECggJEQAAAA==.Allsmiles:BAABLgAECn8VAAQKAAkJZh7tCAAhAgAKAAgJhRrtCAAhAgALAAUJChm2TQBwAQAMAAQJkh4oKgDvAAAAAA==.Allura:BAAALgAECgUJDQAAAA==.Alorian:BAAALgAECgIJAgAAAA==.Alttharius:BAAALgAECgMJAwABLgAECgkJGwANAGMhAA==.Alyysha:BAABLgAECn8bAAIOAAcJlwkCRgBgAQAOAAcJlwkCRgBgAQAAAA==.',
Am='Amoon:BAABLgAECn81AAMPAAkJgBmcKAAoAgAPAAkJ0RecKAAoAgAQAAYJBRXYEgAjAQAAAA==.',
An='Angelrain:BAABLgAECn8sAAMRAAgJWByRDgCaAgARAAgJWByRDgCaAgASAAcJ8QcCPAAFAQAAAA==.Aniata:BAAALgAECgEJAQAAAA==.',
Ar='Archymedes:BAABLgAECn8sAAILAAcJJxFMPgBMAQALAAcJJxFMPgBMAQAAAA==.Arckady:BAAALgAECgQJEgAAAA==.Areko:BAAALgAECgIJBQAAAA==.Aresh:BAAALgAECgEJAgAAAA==.Array:BAAALgAECggJEgABLgAECgkJMAAGAPEeAA==.Artharius:BAABLgAECn8bAAINAAkJYyGpFQALAgANAAkJYyGpFQALAgAAAA==.',
As='Asanad:BAAALgADCgUJBQABLgAECgUJCQATAAAAAA==.',
Au='Auburnbeard:BAAALgADCgYJBgAAAA==.Aumed:BAAALgADCgEJAQAAAA==.Aurelionburn:BAAALgAECgEJAQAAAA==.',
Av='Averle:BAABLgAECn9lAAIDAAcJpwu8FQD8AAADAAcJpwu8FQD8AAAAAA==.',
Az='Azrran:BAAALgADCgEJAQAAAA==.Aztharot:BAAALgAECgIJAgAAAA==.',
Ba='Badchoices:BAAALgAECgQJBAAAAA==.Badkittie:BAAALgAECgQJCgAAAA==.Balding:BAAALgAECgQJCAAAAA==.Baphico:BAAALgADCgUJCQAAAA==.',
Be='Bearhug:BAAALgAECgEJAQAAAA==.Beefsnake:BAEALgAFFAEJAQABLgAFFAUJGwAHABoJAA==.Behemoth:BAAALgAECgQJBAAAAA==.Belinda:BAAALgAECgEJAQABLgAFFAYJHwAUAMgjAA==.Bettyßaraxus:BAAALgAECgMJAwABLgAECgkJMgAVAK8fAA==.Bewater:BAAALgADCgcJBwAAAA==.',
Bi='Bigcarol:BAAALgAECgEJAQAAAA==.Bigunsforu:BAAALgAECgYJCgAAAA==.',
Bl='Bladesmcgee:BAAALgAECggJCQABLgAECgQJCAATAAAAAA==.Blasphem:BAAALgADCgQJBAAAAA==.',
Bo='Bobadelphia:BAAALgADCgYJBgABLgAECgYJEQATAAAAAA==.Bofahdeez:BAABLgAECn8aAAMSAAgJfA6+PABHAQASAAcJWA6+PABHAQARAAcJLQwEPgAZAQAAAA==.Bogs:BAACLgAFFH8YAAIIAAUJmx2XSgBMAQAIAAUJmx2XSgBMAQAuAAQKfyMAAggACAnrIb4jAOQCAAgACAnrIb4jAOQCAAAA.Bonedaddy:BAAALgAECgYJBgAAAA==.Boomstick:BAAALgAFFAEJAQABLgAFFAUJEgAPAB8OAA==.',
Br='Brewswayne:BAAALgADCgQJBAABLgAFFAIJAwATAAAAAA==.Brolic:BAABLgAECn87AAMWAAkJuyEGBAAOAwAWAAkJuyEGBAAOAwAPAAEJJgnZKQEkAAAAAA==.',
['Bä']='Bämboo:BAAALgAFFAEJAgABLgAFFAUJDAAXACsVAA==.',
Ca='Cail:BAEBLgAECn8ZAAIXAAkJexYfIABPAgAXAAkJexYfIABPAgAAAA==.Calamìty:BAAALgADCgcJDgABLgAFFAMJCgAGAJYMAA==.Calisa:BAABLgAECn87AAIYAAkJ6h9nAQDnAgAYAAkJ6h9nAQDnAgAAAA==.Cardio:BAAALgAECgUJBgAAAA==.Carnifexx:BAABLgAFFH8FAAMXAAIJqxQfZAB/AAAXAAIJqxQfZAB/AAAJAAIJggmvSABtAAABLgAFFAIJBQAXAKsUAA==.Cassey:BAAALgAECgEJAQAAAA==.',
Ce='Celesteus:BAAALgADCgkJFAAAAA==.',
Ch='Charis:BAAALgAECgYJCwAAAA==.Chel:BAAALgAECgEJAQAAAA==.Chigutotems:BAAALgAECgYJCwABLgAECgkJGwAPAGwWAA==.Chimmoku:BAABLgAFFH8IAAIBAAQJ6RBEHAA6AQABAAQJ6RBEHAA6AQABLgAFFAcJHQABAD4ZAA==.Choi:BAAALgAECgUJDwAAAA==.Chooq:BAAALgADCgIJAgAAAA==.Chozen:BAAALgAECgUJEAAAAA==.Chumlee:BAAALgAECgYJDgAAAA==.',
Ci='Cienna:BAAALgAECgYJDgAAAA==.Cigz:BAAALgADCgEJAQAAAA==.Cinch:BAAALgAECgIJAgAAAA==.',
Co='Colinferral:BAAALgAECgYJCAAAAA==.Coulee:BAAALgAECgQJCAABLgAFFAMJBwAWAGkgAA==.Cowladin:BAAALgADCgUJBQAAAA==.',
Cr='Crakzkull:BAAALgAECgUJCwAAAA==.Croar:BAAALgAECgMJBAAAAA==.Cronicpain:BAAALgADCgkJCQAAAA==.',
Cu='Cuernuda:BAAALgAECgEJAQAAAA==.',
['Cä']='Cäntstandya:BAACLgAFFH8RAAMZAAQJVRjeGwDyAAAZAAMJnxfeGwDyAAAaAAMJmRiUZQDaAAAuAAQKfyMAAxoACAkvG1cSAKUCABoACAliGVcSAKUCABkABwkaHj0TAA0CAAAA.',
Da='Daiko:BAAALgAECgYJCQAAAA==.Daks:BAAALgAFFAIJAwAAAA==.Dargo:BAAALgAECgYJEwAAAA==.Darklucrezia:BAACLgAFFH8UAAMaAAUJjhzjMgBIAQAaAAUJjhzjMgBIAQAbAAIJNgLbNQBIAAAuAAQKfy4AAxoACAn3H0UeAHACABoACAltH0UeAHACABsACAkOEeQlAPoBAAAA.Dazzlefraz:BAAALgAECgQJBAAAAA==.',
De='Demonklunter:BAAALgADCgYJEAAAAA==.Denaida:BAAALgAECgEJAQAAAA==.Destructoid:BAAALgAECgEJAQAAAA==.',
Dg='Dgk:BAAALgAECgcJBwAAAA==.',
Dh='Dh:BAAALgAECgMJAwAAAA==.',
Di='Dicey:BAAALgADCgMJAwABLgAECgQJBwATAAAAAA==.',
Do='Dochunter:BAAALgAECgUJBQAAAA==.',
Dr='Dracarius:BAABLgAECn8YAAQcAAUJwxaRDwASAQAcAAQJwxaRDwASAQAHAAMJIwvCdQB7AAAdAAIJ5QObAgAgAAAAAA==.Drega:BAAALgAECgYJBwAAAA==.Droods:BAAALgAECgQJBQAAAA==.Drtypinkcake:BAABLgAECn8iAAIWAAkJ9wnXJABRAQAWAAkJ9wnXJABRAQAAAA==.Druskgar:BAABLgAECn8qAAMUAAkJMx8sMAA+AgAUAAkJMx8sMAA+AgAeAAcJ4A8rIwA5AQAAAA==.Dryad:BAABLgAECn8XAAIfAAUJNgzUAwBgAAAfAAUJNgzUAwBgAAAAAA==.',
Du='Duckster:BAAALgADCgYJBwAAAA==.Dunce:BAACLgAFFH8GAAIgAAIJdR+oPQCuAAAgAAIJdR+oPQCuAAAuAAQKfygAAiAACAnyIJ4NAMMCACAACAnyIJ4NAMMCAAAA.Durkk:BAABLgAECn87AAIeAAkJ9yF0BQDSAgAeAAkJ9yF0BQDSAgAAAA==.Durza:BAAALgAECgcJEAAAAA==.',
['Dä']='Dännydevito:BAAALgADCgQJBAAAAA==.',
Ea='Easyheal:BAAALgAECgUJBgAAAA==.',
Ed='Eduard:BAAALgAECgYJCQAAAA==.',
Ek='Eklipse:BAAALgAECgMJAwAAAA==.',
El='Elanthae:BAAALgAECgQJEQAAAA==.Elysia:BAAALgAECgEJAgAAAA==.',
Er='Erzulie:BAAALgAECgUJBAAAAA==.',
Es='Estara:BAABLgAECn81AAIfAAkJqwtcJgAhAQAfAAkJqwtcJgAhAQAAAA==.',
Et='Etali:BAABLgAECn8yAAILAAkJQBwJEQBuAgALAAkJQBwJEQBuAgAAAA==.',
Ex='Expired:BAAALgAECgEJAQAAAA==.',
Fa='Faite:BAAALgADCgUJBQAAAA==.Falorin:BAACLgAFFH8HAAIIAAIJXg5WogCKAAAIAAIJXg5WogCKAAAuAAQKfyEAAggACQm7FZJjALcBAAgACQm7FZJjALcBAAAA.Fanis:BAABLgAECn8mAAIbAAkJzRXLCQDYAQAbAAkJzRXLCQDYAQAAAA==.Fatherwhig:BAAALgAECgIJAwAAAA==.',
Fe='Fenrin:BAAALgAECgQJBwAAAA==.',
Fi='Fidis:BAAALgADCgkJCwAAAA==.Fistsofdeath:BAAALgADCggJCgAAAA==.Fistychub:BAAALgADCgEJAQAAAA==.',
Fl='Flashbang:BAAALgADCgEJAQAAAA==.Flashis:BAAALgAECggJEwAAAA==.Florago:BAABLgAECn8YAAIEAAUJiQfPAQB3AAAEAAUJiQfPAQB3AAAAAA==.',
Fr='Frakir:BAABLgAECn87AAQXAAkJ5xlMGQCAAgAXAAkJ5xlMGQCAAgAhAAMJRwq0LQCLAAAJAAEJkAYjkwAjAAAAAA==.Fritzz:BAAALgAECgcJEgABLgAECgkJFAAFACcXAA==.Frog:BAAALgAECgIJBQAAAA==.',
Fu='Furrypaw:BAABLgAECn8uAAIgAAkJZiXMAQC8AwAgAAkJZiXMAQC8AwAAAA==.Fuzzyy:BAAALgAECgEJAQAAAA==.',
Fw='Fwapp:BAACLgAFFH8bAAIOAAgJKRtwCAA5AgAOAAgJKRtwCAA5AgAuAAQKfxcAAg4ACAlrIcgLAL8CAA4ACAlrIcgLAL8CAAAA.',
Ga='Galvanize:BAAALgAECgEJBAABLgAECgcJHAAUALoWAA==.Galynisse:BAABLgAECn8yAAMiAAgJAhjKFAA2AgAiAAgJAhjKFAA2AgASAAMJ7A4eZQCZAAAAAA==.',
Ge='Gedorah:BAABLgAECn8fAAIjAAcJOBy1AwDYAQAjAAcJOBy1AwDYAQABLgAFFAQJFAAJAGMhAA==.',
Gh='Ghaspy:BAAALgAECgUJCgAAAA==.Ghoste:BAAALgADCgMJAwAAAA==.Ghrex:BAAALgAECgEJAQAAAA==.',
Gi='Gijaick:BAABLgAECn8wAAMCAAgJWBgGRwDFAQACAAgJWBgGRwDFAQADAAEJHg4AdAAxAAAAAA==.',
Gl='Glaivethrow:BAABLgAECn8bAAIPAAkJbBZXPwDLAQAPAAkJbBZXPwDLAQAAAA==.Glizzo:BAAALgAECgYJDAAAAA==.Gloam:BAAALgADCgUJBQAAAA==.Gloomrider:BAAALgADCgMJAwAAAA==.Glueballs:BAAALgAECgEJAQABLgAECgcJDAATAAAAAA==.',
Go='Gochujjang:BAAALgAECgYJDQAAAA==.Goldhawk:BAAALgAECgMJAwAAAA==.Gotchá:BAAALgAECgEJBAAAAA==.Gotwiped:BAABLgAECn8WAAIUAAgJfRqhOwASAgAUAAgJfRqhOwASAgAAAA==.',
Gr='Grimgor:BAAALgAECgcJAQAAAA==.',
Ha='Hahaheals:BAAALgAECgMJBAAAAA==.Hakhar:BAAALgADCgMJAwAAAA==.Hanth:BAAALgADCgkJDAABLgAECgMJBAATAAAAAA==.Hatter:BAABLgAECn8pAAQPAAgJ4xXLQgC/AQAPAAgJ4xXLQgC/AQAWAAMJ+AsRWACGAAAQAAEJNRMmKwA0AAAAAA==.',
He='Healsus:BAAALgAECgMJAwAAAA==.Heimlish:BAAALgAECgEJAQAAAA==.Hellraiser:BAABLgAECn8pAAMUAAkJORgdNwAiAgAUAAkJWhcdNwAiAgAeAAcJaRNCIABRAQAAAA==.Hermione:BAAALgAECgYJDQAAAA==.Hexecution:BAAALgADCgIJAgAAAA==.',
Hi='Hiddendragon:BAAALgAECgEJAQAAAA==.',
Ho='Holydarkness:BAAALgAECgYJCwAAAA==.Holyhello:BAAALgAECgEJAQAAAA==.Holykilla:BAAALgAECgEJBQAAAA==.Holykiller:BAAALgAECgcJCgAAAA==.Hoofjob:BAAALgADCggJDgABLgAFFAUJDwAiAEccAA==.Hoplite:BAAALgADCgcJDgABLgAECggJEgATAAAAAA==.Hotot:BAAALgADCgMJAwAAAA==.Howlly:BAABLgAECn8hAAIIAAkJDBQfAQDZAQAIAAkJDBQfAQDZAQAAAA==.',
Hu='Huffpuffle:BAAALgAECgUJCgAAAA==.',
['Hô']='Hôwl:BAABLgAECn8YAAIGAAcJwhBHSABuAQAGAAcJwhBHSABuAQAAAA==.',
Ic='Icdeathg:BAACLgAFFH8JAAIPAAMJ/QsdbACzAAAPAAMJ/QsdbACzAAAuAAQKfzEAAg8ACAksH2IaAHYCAA8ACAksH2IaAHYCAAAA.',
Ik='Iktaar:BAAALgAECgYJEQAAAA==.',
Il='Illidami:BAAALgADCgkJCwAAAA==.Illidamngirl:BAAALgADCgYJBgABLgAECgkJKQAMANkcAA==.',
Im='Imperius:BAACLgAFFH8VAAIVAAUJHBYITAAVAQAVAAUJHBYITAAVAQAuAAQKfyQAAhUACQmMJB0OAB0DABUACQmMJB0OAB0DAAAA.',
In='Ines:BAACLgAFFH8KAAIUAAMJWSEvhwD7AAAUAAMJWSEvhwD7AAAuAAQKfzoAAhQACQlrJHELABIDABQACQlrJHELABIDAAAA.Insomiax:BAAALgAECggJDwAAAA==.Insta:BAABLgAECn8rAAILAAcJzx3cIwA3AgALAAcJzx3cIwA3AgAAAA==.Inter:BAABLgAECn8vAAIeAAkJ9yE6BAALAwAeAAkJ9yE6BAALAwAAAA==.',
Ir='Iridi:BAAALgADCgEJAQAAAA==.Iritall:BAAALgADCgcJCwABLgAECgEJAgATAAAAAA==.',
It='Ithamburglar:BAAALgAECgQJBwAAAA==.',
Iz='Izureka:BAAALgADCgYJBgAAAA==.',
Ja='Jackidaytona:BAAALgAECgcJBwAAAA==.Jakaru:BAABLgAECn8bAAIgAAkJWRqZEgCJAgAgAAkJWRqZEgCJAgAAAA==.Jankadish:BAAALgAECgcJEwAAAA==.Jarre:BAACLgAFFH8GAAIGAAQJrggsDgAFAQAGAAQJrggsDgAFAQAuAAQKfygAAgYACAmzICIKAPMCAAYACAmzICIKAPMCAAAA.Jaspirian:BAAALgADCggJFAAAAA==.Jazzil:BAAALgADCgcJCgAAAA==.',
Jb='Jbaconcheese:BAAALgAECgEJAQAAAA==.',
Je='Jehm:BAAALgAECgIJAgABLgAECgMJAwATAAAAAA==.Jehmkin:BAAALgAECgEJAQAAAA==.Jehmothy:BAAALgAECgUJBQAAAA==.Jerome:BAAALgAECgEJAQAAAA==.',
Jo='Jotabop:BAAALgAECgQJBgAAAA==.',
Ju='Judgequota:BAAALgAFFAMJAwABLgAFFAUJEgAJACceAA==.Juggsgotcha:BAABLgAFFH8FAAIUAAMJiw1sCgDTAAAUAAMJiw1sCgDTAAAAAA==.Juicy:BAABLgAECn8kAAIZAAkJQRerDQBMAgAZAAkJQRerDQBMAgAAAA==.Juupiter:BAAALgAECgEJAQABLgAFFAIJBwAIAF4OAA==.',
Ka='Kabu:BAAALgAECgcJBwAAAA==.Kalia:BAABLgAECn8vAAMIAAkJ/xgVPgB/AgAIAAkJ/xgVPgB/AgAkAAMJUg8vDgCXAAAAAA==.Kalitra:BAAALgADCgMJAwABLgAECgkJLwAIAP8YAA==.Katatonik:BAAALgAECgQJBgAAAA==.Katharina:BAAALgAECgcJBwABLgAFFAEJAQATAAAAAA==.Katoumae:BAACLgAFFH8SAAIlAAUJNB2rBgBCAQAlAAUJNB2rBgBCAQAuAAQKfy4ABCUACQmkI6UCAPkCACUACQk5IqUCAPkCAB8AAwm4FL0CAH0AAAUAAQlKGUcFAEkAAAAA.Katoumey:BAAALgAECgYJCgABLgAFFAUJEgAlADQdAA==.',
Ke='Keratin:BAABLgAECn8uAAImAAkJvSIhBACRAgAmAAkJvSIhBACRAgAAAA==.',
Kh='Khumi:BAABLgAECn8XAAIbAAgJYSCmEgCiAgAbAAgJYSCmEgCiAgABLgAFFAkJLwAVAEMmAA==.',
Ki='Kinan:BAABLgAECn82AAMaAAkJHSYDAgB0AwAaAAkJHSYDAgB0AwAbAAcJOx6kFwBxAgAAAA==.Kita:BAAALgAECggJEgABLgAECgkJAgATAAAAAA==.',
Kk='Kkaarrkk:BAAALgAECgUJCAAAAA==.',
Kr='Kreloenis:BAAALgAECgIJAgAAAA==.Krindon:BAABLgAECn8pAAIWAAgJIBLTHQCNAQAWAAgJIBLTHQCNAQAAAA==.',
Ku='Kureiji:BAAALgADCgEJAQAAAA==.',
Ky='Kythin:BAAALgAECgEJAgABLgAECgkJLwAIAP8YAA==.',
La='Lacutis:BAAALgAECgEJBAAAAA==.Lanssolo:BAABLgAECn8UAAIVAAgJYgbGBwCNAAAVAAgJYgbGBwCNAAAAAA==.Laww:BAAALgADCgcJCgAAAA==.',
Le='Lecroix:BAAALgADCgUJBQAAAA==.Leonus:BAAALgAECgMJAwABLgAECgIJAgATAAAAAA==.Lessana:BAAALgAECgQJDgAAAA==.Lethalforce:BAAALgADCgMJAwAAAA==.',
Li='Liandri:BAAALgADCgEJAgAAAA==.Lightchild:BAAALgADCggJCAAAAA==.Lightprivlge:BAAALgAECgcJDQABLgAECgcJHAAUALoWAA==.Lillith:BAAALgAECgMJAwAAAA==.Livewire:BAABLgAECn8YAAMJAAUJCyJ9AQAMAQAJAAQJCyJ9AQAMAQAXAAEJqhwtvgBTAAAAAA==.',
Lo='Lokohmojo:BAAALgAECgMJBAAAAA==.Lomponic:BAEBLgAECn81AAIRAAkJvR2qDwBhAgARAAkJvR2qDwBhAgAAAA==.Loomadin:BAAALgADCgYJCQAAAA==.Loranis:BAAALgAECgQJBwAAAA==.',
Lu='Lunethra:BAABLgAECn8rAAIaAAkJwhGAKwAGAgAaAAkJwhGAKwAGAgAAAA==.',
Ma='Mageaux:BAAALgAECgEJAgAAAA==.Magerag:BAACLgAFFH8JAAIIAAMJGBuCewDgAAAIAAMJGBuCewDgAAAuAAQKfy8AAwgACQlNIoEhAJgCAAgACQlNIoEhAJgCACQAAglAGkQVAHMAAAAA.Manamontana:BAACLgAFFH8bAAMUAAgJbw6+HwD1AQAUAAcJbw6+HwD1AQAeAAEJAACiUAAAAAAuAAQKfxoAAhQACAn4H4AoAJgCABQACAn4H4AoAJgCAAAA.Marumo:BAAALgAECgMJBgAAAA==.',
Mc='Mcribz:BAACLgAFFH8fAAIUAAYJyCPqIgDkAQAUAAYJyCPqIgDkAQAuAAQKfyIAAhQACAl8IzIZAOUCABQACAl8IzIZAOUCAAAA.',
Me='Meelonusk:BAAALgAECgQJCAAAAA==.Mess:BAAALgAECgYJDAAAAA==.Messah:BAAALgAECgQJCgAAAA==.Messic:BAAALgADCgEJAQAAAA==.',
Mi='Michaelcoyle:BAACLgAFFH8LAAIaAAQJLhCdBgDtAAAaAAQJLhCdBgDtAAAuAAQKfzQAAhoACAnuHi8hAGECABoACAnuHi8hAGECAAAA.Midnightcrow:BAAALgADCgkJDwAAAA==.Milo:BAACLgAFFH8RAAILAAQJFiHzDwCGAQALAAQJFiHzDwCGAQAuAAQKfzcAAwsACQlFI3cGAPcCAAsACQlFI3cGAPcCAAoACAluHBQEALQCAAAA.Minlessu:BAAALgADCgEJAQAAAA==.Miorine:BAAALgAECgEJAgAAAA==.Mishra:BAAALgAECgUJBQAAAA==.Mitra:BAABLgAECn8+AAIYAAkJYiONAAA/AwAYAAkJYiONAAA/AwAAAA==.',
Mo='Moesko:BAACLgAFFH8HAAIGAAMJzQszSACXAAAGAAMJzQszSACXAAAuAAQKfxUAAgYACQlwEto+AJYBAAYACQlwEto+AJYBAAAA.Mof:BAAALgADCgEJAQAAAA==.Mohawkk:BAAALgAECgQJBQAAAA==.Monktup:BAAALgAECgYJCwAAAA==.Monnehbaggs:BAABLgAECn8xAAMiAAkJthyyDQCSAgAiAAgJ4RuyDQCSAgASAAgJpR3/DQB7AgAAAA==.Mortalidad:BAAALgADCgQJBAAAAA==.',
Mu='Muin:BAAALgAECgEJAQAAAA==.Murdersamich:BAAALgAECgQJCwAAAA==.',
My='Mybigcrits:BAAALgAECgYJDAAAAA==.Myraghor:BAAALgADCgYJBgAAAA==.',
['Mà']='Màevë:BAAALgAECgEJAgAAAA==.',
Na='Nairdax:BAAALgADCgEJAQAAAA==.Nalmec:BAABLgAECn8hAAILAAYJPQhNXgDaAAALAAYJPQhNXgDaAAAAAA==.Nama:BAAALgADCgcJFAAAAA==.Naysayre:BAABLgAECn8wAAIPAAgJ4AdRiQAOAQAPAAgJ4AdRiQAOAQAAAA==.',
Ne='Nebody:BAAALgAECgYJDwAAAA==.Necriss:BAABLgAECn8sAAIVAAkJUxD6ZACmAQAVAAkJUxD6ZACmAQAAAA==.Nevereven:BAAALgAECgEJAQAAAA==.',
Ni='Nightkilla:BAAALgAECgEJAwAAAA==.Nike:BAAALgAECggJEAAAAA==.Nilowin:BAABLgAECn82AAIBAAkJCxFkFwDgAQABAAkJCxFkFwDgAQAAAA==.',
No='Nokaj:BAAALgAECgEJAgAAAA==.Noshards:BAAALgAECgcJDQAAAA==.Notericdh:BAAALgAECgYJEwAAAA==.',
Og='Oghom:BAAALgADCgcJCgAAAA==.',
Oh='Ohnoitzgumby:BAABLgAECn8cAAMUAAcJuhbubACLAQAUAAcJrBbubACLAQAmAAMJoBJPFABOAAAAAA==.',
Om='Omiko:BAAALgAECgIJAgAAAA==.',
Op='Opeep:BAAALgADCgcJGQAAAA==.',
Or='Orah:BAAALgADCgEJAQAAAA==.',
Os='Osos:BAAALgAECgYJEAAAAA==.',
Pa='Paladimdab:BAAALgAECgQJBQAAAA==.Papachance:BAABLgAECn8cAAIIAAgJhgiSnwA8AQAIAAgJhgiSnwA8AQAAAA==.Papafrank:BAAALgAECgYJDQAAAA==.Paradis:BAAALgADCgcJBwAAAA==.Pazuzu:BAAALgADCgYJBgAAAA==.',
Pe='Peepo:BAAALgAECgEJAQAAAA==.',
Ph='Phoenixwing:BAAALgADCgYJBgAAAA==.',
Pi='Pinga:BAACLgAFFH8GAAIiAAMJjgoXNQC3AAAiAAMJjgoXNQC3AAAuAAQKfyIABCIACQkhICkFADkDACIACQkhICkFADkDABIAAgn6HOZfAFwAABEAAQmZDjyJADAAAAEuAAUUBAkJAB0AeBYA.Pinkberry:BAAALgAECgQJBAAAAA==.Pintcube:BAAALgADCgYJCAAAAA==.',
Pl='Pljeskavica:BAAALgAECgYJBwAAAA==.Plox:BAAALgAECgMJAwAAAA==.',
Po='Port:BAABLgAECn8wAAIGAAkJ8R6NDAD6AgAGAAkJ8R6NDAD6AgAAAA==.Potroastjr:BAAALgAECgEJAQABLgAECgEJAQATAAAAAA==.',
Pr='Preposition:BAAALgAECgcJBwAAAA==.Primordus:BAAALgADCgUJBQAAAA==.Profiler:BAAALgAECgcJCgAAAA==.Protocol:BAAALgAECgMJAwAAAA==.Prïestess:BAAALgAECgcJDAAAAA==.',
Ps='Pseriph:BAABLgAECn8ZAAIDAAcJ3BZrCwAKAgADAAcJ3BZrCwAKAgAAAA==.',
Ra='Radamantis:BAAALgAECgQJBwAAAA==.Raenon:BAAALgAECgEJAQAAAA==.Raggnar:BAACLgAFFH8UAAIJAAQJYyFtFQBxAQAJAAQJYyFtFQBxAQAuAAQKfzEAAgkACQmVIakHAOICAAkACQmVIakHAOICAAAA.Ragingwaters:BAAALgADCgYJCAABLgAECgIJBgATAAAAAA==.Ranvir:BAAALgAECgYJCAAAAA==.Raun:BAABLgAECn87AAMVAAkJBiPDCQAZAwAVAAkJBiPDCQAZAwAOAAMJJBEvcgCzAAAAAA==.',
Re='Regnarr:BAAALgADCgEJAQAAAA==.Rehgar:BAAALgAFFAEJAQAAAA==.Relaire:BAABLgAECn9KAAIaAAkJTxQ9AwAtAQAaAAkJTxQ9AwAtAQAAAA==.Remenissions:BAAALgAECgEJAQAAAA==.Resonate:BAAALgAFFAIJAwAAAA==.',
Ri='Rikane:BAAALgADCgcJDAABLgADCgcJEgATAAAAAA==.Rikenji:BAAALgAECgEJAQABLgAFFAIJBwAIAF4OAA==.Riku:BAABLgAECn82AAIlAAkJvSDSAgDzAgAlAAkJvSDSAgDzAgAAAA==.',
Ro='Rock:BAAALgAECgcJEgAAAA==.Rocks:BAAALgAECgEJAQAAAA==.Rockyrag:BAAALgAECgUJBQAAAA==.Roguey:BAABLgAECn8sAAMnAAkJuQ9LDABoAQAnAAcJlBFLDABoAQABAAcJ/wxHKQBNAQAAAA==.Roots:BAAALgAECgEJCAAAAA==.',
Ru='Rulethrefour:BAAALgAECgQJCAABLgAECgcJHAAUALoWAA==.',
Ry='Ryveri:BAABLgAECn8lAAILAAkJDxnCHQAAAgALAAkJDxnCHQAAAgAAAA==.',
Sa='Sablehide:BAABLgAECn81AAIHAAkJ4BntEQBUAgAHAAkJ4BntEQBUAgAAAA==.Sanaron:BAAALgADCgIJAgAAAA==.Sanaty:BAAALgAFFAIJBAAAAA==.Sarnak:BAAALgADCgMJAwAAAA==.Saryn:BAAALgAECgYJDwAAAA==.Satanz:BAAALgADCgIJAgAAAA==.Sathanus:BAAALgAECgUJEwAAAA==.Sathir:BAAALgADCgMJAwAAAA==.',
Se='Searate:BAAALgADCgcJEgAAAA==.Seaside:BAACLgAFFH8PAAIUAAMJ/iX3HAAvAQAUAAMJ/iX3HAAvAQAuAAQKfxgAAxQABwk9JfJEAPMBABQABwk9JfJEAPMBAB4AAgmEC+8/AE4AAAAA.Secrett:BAABLgAECn8dAAMBAAcJkhVOJQBrAQABAAcJkhVOJQBrAQAnAAEJew5fKQAwAAAAAA==.Sephyxia:BAABLgAECn8vAAIeAAkJdBqoDgAhAgAeAAkJdBqoDgAhAgAAAA==.Serryon:BAAALgADCgIJAgAAAA==.',
Sf='Sfora:BAAALgAECgUJBQAAAA==.',
Sh='Shadowreaper:BAAALgADCgYJBQAAAA==.Shadowwzz:BAAALgADCgEJAQAAAA==.Shocknezz:BAAALgAECgYJCAAAAA==.Shockwaves:BAAALgAECgEJAQAAAA==.Shoçknezz:BAAALgAECgMJBQAAAA==.',
Si='Silverwolf:BAABLgAECn9GAAIhAAkJ/SC2AgDqAgAhAAkJ/SC2AgDqAgAAAA==.Simplyunlock:BAACLgAFFH8cAAMCAAUJIgxVCQCyAAACAAQJIgxVCQCyAAAEAAEJAADYMQAAAAAuAAQKfycAAwIACQnzE4Y0AAcCAAIACQnzE4Y0AAcCAAMAAgnnBZVmAEMAAAAA.Simplyvoided:BAAALgAECgQJBgAAAA==.Sinfulcynic:BAAALgADCgQJBQAAAA==.Sinverguenza:BAAALgAECgMJBQAAAA==.Sizzlechop:BAABLgAECn8uAAMUAAkJ/g+oiABTAQAUAAgJ7QqoiABTAQAeAAMJrBYdNQDDAAAAAA==.',
Sk='Skizzak:BAAALgADCgQJBAABLgAFFAYJHwAUAMgjAA==.Skweeks:BAAALgAECgMJBAAAAA==.',
Sm='Smelvin:BAABLgAECn8cAAIJAAkJ8xlcHQD2AQAJAAkJ8xlcHQD2AQABLgAECgQJCAATAAAAAA==.Smoko:BAAALgAECgIJAgABLgAECgUJBQATAAAAAA==.',
Sn='Snailslolol:BAAALgAECgcJCgAAAA==.Snakey:BAECLgAFFH8bAAMHAAUJGgmJPADVAAAHAAQJGgmJPADVAAAcAAIJ1wJVEAA5AAAuAAQKfywAAwcACAmLGD4aAPkBAAcACAmLGD4aAPkBABwABgl5BHkmAO8AAAAA.',
So='Solara:BAABLgAECn8hAAQRAAkJMRhAFwAPAgARAAkJMRhAFwAPAgASAAEJQAIShwApAAAiAAEJXgKYXgAkAAAAAA==.Soleill:BAAALgAECgcJBwAAAA==.Sondan:BAAALgADCgMJAwAAAA==.Songs:BAAALgAECgEJAQABLgAECgYJGAANAP8gAA==.',
Sp='Spellpowa:BAAALgAECgYJDgAAAA==.',
Sq='Squirtin:BAAALgAECgIJAgAAAA==.',
Ss='Ssminion:BAAALgAECgMJBgAAAA==.',
St='Stalath:BAAALgAECgUJCAAAAA==.Stormwing:BAABLgAECn8fAAMJAAgJiBmwJgC2AQAJAAgJiBmwJgC2AQAXAAEJMRY9zABAAAAAAA==.Strecagosa:BAAALgAECgYJDQAAAA==.',
Su='Sumarr:BAAALgAECgYJBgABLgAECgcJBwATAAAAAA==.',
Sv='Svenn:BAAALgAECgYJCAAAAA==.',
Sw='Swiftstrike:BAAALgADCgYJCAAAAA==.',
Sy='Sybelissa:BAAALgAECgMJAwABLgAECgcJCgATAAAAAA==.Synni:BAAALgADCgEJAQAAAA==.',
['Sÿ']='Sÿnÿster:BAAALgAECgQJBQABLgAFFAUJFAAaAI4cAA==.',
Ta='Talron:BAAALgAECgUJCQAAAA==.Tastytay:BAAALgADCgMJAwAAAA==.Tatertots:BAABLgAECn8yAAMmAAkJFCCxAgDYAgAmAAkJFCCxAgDYAgAUAAMJ8hON7ACmAAAAAA==.',
Te='Tea:BAABLgAECn8xAAIaAAkJgCXhAwBSAwAaAAkJgCXhAwBSAwAAAA==.Teal:BAAALgAECgMJAwAAAA==.Templyn:BAABLgAECn81AAMUAAkJZRS2VgDBAQAUAAkJjA62VgDBAQAeAAgJCRZrGgCKAQAAAA==.Templÿn:BAAALgAECgQJBAABLgAECgkJNQAUAGUUAA==.Tenebrarum:BAABLgAECn8bAAIaAAgJGQ0xVwBjAQAaAAgJGQ0xVwBjAQAAAA==.Testorooni:BAABLgAECn8ZAAIaAAcJkBgpMwDjAQAaAAcJkBgpMwDjAQAAAA==.',
Th='Thakodi:BAAALgAECgQJBAAAAA==.Thannos:BAAALgADCgEJAQAAAA==.Tharvan:BAAALgADCgcJDAAAAA==.Thavok:BAAALgAECgEJAQAAAA==.Thedeadman:BAABLgAECn8kAAIUAAkJEyIsJAB0AgAUAAkJEyIsJAB0AgAAAA==.Thepriestg:BAAALgAECgEJAQAAAA==.Thiccksilver:BAAALgADCgcJBwABLgAFFAQJDwACAAUWAA==.Thompson:BAABLgAECn8VAAIUAAcJuxTtkwA/AQAUAAcJuxTtkwA/AQAAAA==.Thunderflaps:BAAALgAECgUJCQAAAA==.Thyrus:BAACLgAFFH8JAAIdAAQJeBYQFwAkAQAdAAQJeBYQFwAkAQAuAAQKfzUAAx0ACQk9Io0DAAwDAB0ACQk9Io0DAAwDABwAAQmqAvtEACMAAAAA.',
Ti='Tirna:BAABLgAECn84AAIjAAkJng5yBACtAQAjAAkJng5yBACtAQAAAA==.',
To='Toebot:BAAALgAECgEJAQAAAA==.Toggle:BAAALgAECgEJAQAAAA==.Tomsellock:BAABLgAECn8WAAMEAAcJjhBuBwDcAQAEAAcJjhBuBwDcAQACAAEJugM+LAEmAAAAAA==.Tonari:BAAALgAECgEJAQABLgAECgYJEAATAAAAAA==.Torvi:BAAALgADCgMJAwAAAA==.',
Tr='Transmørtuus:BAAALgAECgQJCQAAAA==.Treehug:BAAALgAECggJEwAAAA==.Triple:BAAALgAECgQJBwABLgAECgYJEAATAAAAAA==.Trolleonne:BAAALgAECgIJAgAAAA==.',
Tu='Tullen:BAEBLgAECn81AAISAAkJjRGHIgCuAQASAAkJjRGHIgCuAQAAAA==.Turanos:BAABLgAECn8YAAIoAAUJBAu2AgBhAAAoAAUJBAu2AgBhAAAAAA==.',
Tw='Tweyen:BAAALgAECgEJAQAAAA==.Twistedbael:BAAALgAECgUJBQAAAA==.',
Ty='Tyindaris:BAAALgAECgQJCgAAAA==.Tyloregeth:BAABLgAECn8sAAIRAAgJphSDKQCFAQARAAgJphSDKQCFAQAAAA==.',
['Tè']='Tèmplyn:BAAALgADCgEJAQABLgAECgkJNQAUAGUUAA==.',
['Té']='Témplýn:BAAALgADCgEJAQABLgAECgkJNQAUAGUUAA==.',
['Të']='Tëmplýn:BAAALgAECgQJBQABLgAECgkJNQAUAGUUAA==.',
Ul='Ulfrunn:BAAALgADCgYJBgAAAA==.Ultrachad:BAACLgAFFH8jAAIUAAgJYxnhDwBeAgAUAAgJYxnhDwBeAgAuAAQKfx4AAhQACAlNIwUUAAMDABQACAlNIwUUAAMDAAAA.',
Um='Umami:BAABLgAECn8gAAILAAYJ+RhzSgB7AQALAAYJ+RhzSgB7AQAAAA==.',
Un='Unggoy:BAACLgAFFH8nAAQbAAkJHR/8AgAkAgAbAAgJnR38AgAkAgAZAAQJyRQAEgA4AQAaAAMJTByFTgAOAQAuAAQKfygAAxsACQkhJrsBAKYDABsACQkhJrsBAKYDABoAAQnFJe/0AGsAAAAA.Unhollowed:BAAALgAECgIJBAAAAA==.Unholywaters:BAAALgAECgIJBgAAAA==.',
Ur='Urianna:BAAALgAECgYJCwAAAA==.',
Va='Vaelthirion:BAABLgAECn8nAAIIAAgJYxbFTwDsAQAIAAgJYxbFTwDsAQAAAA==.Vahidamus:BAAALgAECggJDAAAAA==.Valkaryon:BAAALgAECgcJCgABLgAFFAIJAwATAAAAAA==.Valmirax:BAAALgADCggJEgAAAA==.Valton:BAABLgAECn9cAAIVAAgJphJuaACeAQAVAAgJphJuaACeAQAAAA==.',
Ve='Vegetation:BAAALgAECgQJBwAAAA==.Velenestus:BAAALgAECgMJBgAAAA==.Verses:BAAALgADCgEJAQAAAA==.',
Vi='Vizsla:BAAALgAECgEJAQAAAA==.',
Wa='Wackaman:BAABLgAECn8pAAIMAAkJ2RxgCQBfAgAMAAkJ2RxgCQBfAgAAAA==.Waffleshirt:BAAALgAECggJDAAAAA==.Warpig:BAAALgAECgYJEQAAAA==.Wasps:BAAALgAECgYJEQAAAA==.',
We='Wegmaniac:BAAALgADCgYJCAAAAA==.Welastrexa:BAAALgADCgUJBQABLgAECgIJBgATAAAAAA==.',
Wi='Wickedclöwn:BAAALgADCgMJAwAAAA==.Winchester:BAAALgADCgIJAgAAAA==.Windhorn:BAABLgAECn8dAAIbAAcJvgeyAADMAAAbAAcJvgeyAADMAAAAAA==.Winds:BAABLgAECn8YAAINAAYJ/yBoFwAqAgANAAYJ/yBoFwAqAgAAAA==.',
Wn='Wntrizcoming:BAAALgADCgMJBQAAAA==.',
Wo='Wolfquota:BAACLgAFFH8SAAIJAAUJJx4RHwAmAQAJAAUJJx4RHwAmAQAuAAQKfyQAAwkACAmCIkkJAP4CAAkACAmCIkkJAP4CACEABAntE08eAOkAAAAA.Wolftime:BAAALgADCgUJBQAAAA==.Wombaa:BAACLgAFFH8ZAAMUAAUJoiX3NACWAQAUAAUJoiX3NACWAQAmAAIJPR79GgCxAAAuAAQKfxwAAhQACAleJGEKAEgDABQACAleJGEKAEgDAAAA.Woolybully:BAAALgAECgEJAQABLgAECgYJBwATAAAAAA==.',
Wr='Wrathbolt:BAAALgAFFAIJAgABLgAFFAQJDwASALsVAA==.Wrathmo:BAACLgAFFH8HAAINAAQJehnCEQAuAQANAAQJehnCEQAuAQAuAAQKfyUAAw0ACAljHG4UABcCAA0ABwlpHm4UABcCACkABwkdCqZAAPgAAAEuAAUUBAkPABIAuxUA.Wrathp:BAABLgAFFH8PAAISAAQJuxXbFgAHAQASAAQJuxXbFgAHAQAAAA==.Wrolie:BAAALgADCgMJAwAAAA==.',
['Wê']='Wêêdyys:BAAALgADCgMJBAAAAA==.',
Xy='Xyr:BAAALgAECgEJAQABLgAECgkJQQARAPUYAA==.',
Ya='Yamiamigo:BAAALgAECgEJAgAAAA==.',
Yo='Yonah:BAAALgAECgEJAQAAAA==.Yougotsniped:BAAALgADCgEJAQAAAA==.',
Za='Zandalia:BAAALgAECgMJAwAAAA==.Zark:BAEALgAECgEJAQABLgAECgkJGQAXAHsWAA==.',
Ze='Zemphoths:BAAALgAECgcJCgAAAA==.',
Zo='Zoa:BAAALgADCgYJBgAAAA==.Zolton:BAAALgADCgMJAwAAAA==.Zornak:BAABLgAECn8fAAICAAYJsw6yAgDrAAACAAYJsw6yAgDrAAAAAA==.',
['Åe']='Åequitas:BAAALgAECgYJCQAAAA==.',
['ßa']='ßahamut:BAAALgAECgYJCQAAAA==.',
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
