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

local lookup = {'Rogue-Subtlety','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Balance','Druid-Restoration','Evoker-Augmentation','Mage-Frost','Shaman-Elemental','Warrior-Arms','Warrior-Fury','Warrior-Protection','Monk-Windwalker','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Shadow','Priest-Holy','Paladin-Retribution','Unknown-Unknown','DeathKnight-Unholy','DemonHunter-Havoc','Shaman-Restoration','Rogue-Outlaw','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Devastation','Evoker-Preservation','DeathKnight-Blood','Druid-Guardian','Monk-Mistweaver','Shaman-Enhancement','Priest-Discipline','Mage-Fire','Mage-Arcane','Druid-Feral','DeathKnight-Frost','Rogue-Assassination','Paladin-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aamon:BAAALgAECgQJCgAAAA==.',
Ab='Abacus:BAABLgAECn8jAAIBAAkJjyLACwBoAgABAAkJjyLACwBoAgAAAA==.',
Ac='Acin:BAAALgADCgQJBAAAAA==.',
Ad='Adam:BAACLgAFFH8gAAQCAAgJWxzAJwCpAQACAAYJax3AJwCpAQADAAMJlBFcDQCiAAAEAAEJECatEwBvAAAuAAQKfy4ABAIACQk2JF4WAM4CAAIACQmcI14WAM4CAAMABQljJKcNAOsBAAQAAQkaI5QvAGAAAAAA.Adedruid:BAABLgAECn8gAAMFAAYJdR9cKwCnAQAFAAYJdR9cKwCnAQAGAAYJ3xoBSgB6AQAAAA==.Adevoker:BAAALgAECgQJBAAAAA==.Adragon:BAABLgAECn8rAAIHAAkJ5RpLDwByAgAHAAkJ5RpLDwByAgAAAA==.',
Ae='Aengyl:BAAALgAECgQJBAAAAA==.Aeonne:BAABLgAECn8WAAIIAAgJyxLYkQBUAQAIAAgJyxLYkQBUAQAAAA==.',
Ak='Akshul:BAABLgAECn8UAAIJAAYJ5Q1HRgAvAQAJAAYJ5Q1HRgAvAQAAAA==.Akurama:BAAALgAECgcJCgAAAA==.',
Al='Alannon:BAAALgADCgUJBQAAAA==.Aldrea:BAAALgAECggJEgAAAA==.Allsmiles:BAABLgAECn8VAAQKAAkJZh7tCAAhAgAKAAgJhRrtCAAhAgALAAUJChm2TQBwAQAMAAQJkh4oKgDvAAAAAA==.Allura:BAAALgAECgUJEAAAAA==.Alorian:BAAALgAECgIJAgAAAA==.Alttharius:BAAALgAECgMJAwABLgAECgkJGwANAGMhAA==.Alyysha:BAABLgAECn8bAAIOAAcJlwkCRgBgAQAOAAcJlwkCRgBgAQAAAA==.',
Am='Amoon:BAABLgAECn81AAMPAAkJgBmXKAAoAgAPAAkJ0ReXKAAoAgAQAAYJBRXYEgAjAQAAAA==.',
An='Angelrain:BAABLgAECn8sAAMRAAgJWByRDgCaAgARAAgJWByRDgCaAgASAAcJ8QcGPAAFAQAAAA==.Aniata:BAAALgAECgEJAQAAAA==.',
Ar='Archymedes:BAABLgAECn8sAAILAAcJJxFLPgBMAQALAAcJJxFLPgBMAQAAAA==.Arckady:BAABLgAECn8VAAITAAQJmhwDCQAYAQATAAQJmhwDCQAYAQAAAA==.Areko:BAAALgAECgIJBQAAAA==.Aresh:BAAALgAECgEJAgAAAA==.Array:BAAALgAECggJEgABLgAECgkJMAAGAPEeAA==.Artharius:BAABLgAECn8bAAINAAkJYyGpFQALAgANAAkJYyGpFQALAgAAAA==.',
As='Asanad:BAAALgADCgUJBQABLgAECgYJDQAUAAAAAA==.',
Au='Auburnbeard:BAAALgADCgYJBgAAAA==.Aumed:BAAALgADCgEJAQAAAA==.Aurelionburn:BAAALgAECgEJAgAAAA==.',
Av='Averle:BAABLgAECn9sAAIDAAcJGQ6+FQD8AAADAAcJGQ6+FQD8AAAAAA==.',
Ay='Ayahuascero:BAAALgAECgEJAQAAAA==.',
Az='Azrran:BAAALgADCgEJAQAAAA==.Aztharot:BAAALgAECgIJBAAAAA==.',
Ba='Badchoices:BAAALgAECgQJBAAAAA==.Badkittie:BAAALgAECgQJDQAAAA==.Balding:BAAALgAECgQJCAAAAA==.Baphico:BAAALgADCgUJCQAAAA==.',
Be='Bearhug:BAAALgAECgEJAQAAAA==.Beefsnake:BAEALgAFFAEJAQABLgAFFAUJGwAHABoJAA==.Behemoth:BAAALgAECgQJBAAAAA==.Belinda:BAAALgAECgEJAQABLgAFFAYJIAAVAMgjAA==.Bettyßaraxus:BAAALgAECgMJAwABLgAECgkJMgATAK8fAA==.Bettyßlight:BAAALgAECgQJBQABLgAECgkJMgATAK8fAA==.Bewater:BAAALgADCgcJBwAAAA==.',
Bi='Bigcarol:BAAALgAECgEJAQAAAA==.Bigunsforu:BAAALgAECgYJEAAAAA==.',
Bl='Bladesmcgee:BAAALgAECggJCQABLgAECgQJCAAUAAAAAA==.Blasphem:BAAALgADCgQJBAAAAA==.',
Bo='Bobadelphia:BAAALgADCgYJBgABLgAECgYJEQAUAAAAAA==.Bofahdeez:BAABLgAECn8aAAMSAAgJfA6+PABHAQASAAcJWA6+PABHAQARAAcJLQwIPgAZAQAAAA==.Bogs:BAACLgAFFH8YAAIIAAUJmx13SgBNAQAIAAUJmx13SgBNAQAuAAQKfyMAAggACAnrIb4jAOQCAAgACAnrIb4jAOQCAAAA.Bonedaddy:BAAALgAECgYJBgAAAA==.Boomstick:BAAALgAFFAEJAQABLgAFFAUJEgAPAB8OAA==.',
Br='Brewswayne:BAAALgADCgQJBAABLgAFFAIJAwAUAAAAAA==.Brolic:BAABLgAECn87AAMWAAkJuyEEBAAOAwAWAAkJuyEEBAAOAwAPAAEJJgnfKQEkAAAAAA==.',
['Bä']='Bämboo:BAAALgAFFAEJAgABLgAFFAUJDAAXACsVAA==.',
Ca='Cail:BAEBLgAECn8ZAAIXAAkJexYhIABPAgAXAAkJexYhIABPAgAAAA==.Calamìty:BAAALgADCgcJDgABLgAFFAMJCgAGAJYMAA==.Calisa:BAABLgAECn87AAIYAAkJ6h9nAQDnAgAYAAkJ6h9nAQDnAgAAAA==.Cardio:BAAALgAECgUJBgAAAA==.Carnifexx:BAABLgAFFH8GAAMXAAIJqxQfZAB/AAAXAAIJqxQfZAB/AAAJAAIJggmtSABtAAABLgAFFAIJBgAXAKsUAA==.Cassey:BAAALgAECgEJAQAAAA==.',
Ce='Celesteus:BAAALgADCgkJFAAAAA==.',
Ch='Charis:BAAALgAECgYJCwAAAA==.Chel:BAAALgAECgEJAQAAAA==.Chigutotems:BAAALgAECgYJCwABLgAECgkJGwAPAGwWAA==.Chimmoku:BAABLgAFFH8IAAIBAAQJ6RA/HAA6AQABAAQJ6RA/HAA6AQABLgAFFAgJHgABAJIWAA==.Choi:BAAALgAECgUJDwAAAA==.Chooq:BAAALgADCgIJAgAAAA==.Chozen:BAAALgAECgUJEAAAAA==.Chumlee:BAAALgAECgYJDgAAAA==.',
Ci='Cienna:BAAALgAECgYJDgAAAA==.Cigz:BAAALgADCgEJAQAAAA==.Cinch:BAAALgAECgIJAgAAAA==.',
Co='Colinferral:BAAALgAECgYJCAAAAA==.Coulee:BAAALgAECgQJCAABLgAFFAMJCAAWAGkgAA==.Cowladin:BAAALgADCgUJBQAAAA==.',
Cr='Crakzkull:BAAALgAECgUJCwAAAA==.Croar:BAAALgAECgMJBAAAAA==.Cronicpain:BAAALgADCgkJCQAAAA==.',
Cu='Cuernuda:BAAALgAECgEJAQAAAA==.',
['Cä']='Cäntstandya:BAACLgAFFH8RAAMZAAQJVRjeGwDyAAAZAAMJnxfeGwDyAAAaAAMJmRiVZQDaAAAuAAQKfyMAAxoACAkvG1cSAKUCABoACAliGVcSAKUCABkABwkaHjsTAA0CAAAA.',
Da='Daiko:BAAALgAECgYJCQAAAA==.Daks:BAAALgAFFAIJAwAAAA==.Dargo:BAAALgAECgYJEwAAAA==.Darklucrezia:BAACLgAFFH8UAAMaAAUJjhzfMgBIAQAaAAUJjhzfMgBIAQAbAAIJNgLRNQBIAAAuAAQKfy4AAxoACAn3H0QeAHACABoACAltH0QeAHACABsACAkOEeQlAPoBAAAA.Dazzlefraz:BAAALgAECgQJBAAAAA==.',
De='Demonklunter:BAAALgADCgYJEAAAAA==.Denaida:BAAALgAECgIJAgAAAA==.Destructoid:BAAALgAECgEJAQAAAA==.',
Dg='Dgk:BAAALgAECgcJBwABLgAECgcJDAAUAAAAAA==.',
Dh='Dh:BAAALgAECgMJAwAAAA==.',
Di='Dicey:BAAALgADCgMJAwABLgAECgQJBwAUAAAAAA==.Dinkler:BAAALgAECgcJBwAAAA==.',
Do='Dochunter:BAAALgAECgUJBQAAAA==.',
Dr='Dracarius:BAABLgAECn8bAAQcAAUJwxaRDwASAQAcAAQJwxaRDwASAQAHAAMJIwvCdQB7AAAdAAIJAAQ2BgAhAAAAAA==.Drega:BAAALgAECgYJBwAAAA==.Droods:BAAALgAECgQJBQAAAA==.Drtypinkcake:BAABLgAECn8iAAIWAAkJ9wnbJABRAQAWAAkJ9wnbJABRAQAAAA==.Druskgar:BAABLgAECn8qAAMVAAkJMx8sMAA+AgAVAAkJMx8sMAA+AgAeAAcJ4A8sIwA5AQAAAA==.Dryad:BAABLgAECn8aAAIfAAUJow0lBwB+AAAfAAUJow0lBwB+AAAAAA==.',
Du='Duckster:BAAALgADCgYJBwAAAA==.Dunce:BAACLgAFFH8HAAIgAAIJdR+sPQCuAAAgAAIJdR+sPQCuAAAuAAQKfygAAiAACAnyIJsNAMMCACAACAnyIJsNAMMCAAAA.Durkk:BAABLgAECn87AAIeAAkJ9yFxBQDSAgAeAAkJ9yFxBQDSAgAAAA==.Durza:BAAALgAECgcJEAAAAA==.',
['Dä']='Dännydevito:BAAALgADCgQJBAAAAA==.',
Ea='Easyheal:BAAALgAECgUJCgAAAA==.',
Ed='Eduard:BAAALgAECgYJCQAAAA==.',
Ek='Eklipse:BAAALgAECgMJAwAAAA==.',
El='Elanthae:BAAALgAECgQJEQAAAA==.Elysia:BAAALgAECgEJAgAAAA==.',
Er='Erzulie:BAAALgAECgUJBAAAAA==.',
Es='Estara:BAABLgAECn81AAIfAAkJqwtbJgAhAQAfAAkJqwtbJgAhAQAAAA==.',
Et='Etali:BAABLgAECn8yAAILAAkJQBwJEQBuAgALAAkJQBwJEQBuAgAAAA==.',
Ex='Expired:BAAALgAECgEJAQAAAA==.',
Fa='Faite:BAAALgADCgUJBQAAAA==.Falorin:BAACLgAFFH8HAAIIAAIJXg5HogCKAAAIAAIJXg5HogCKAAAuAAQKfyEAAggACQm7FZNjALcBAAgACQm7FZNjALcBAAAA.Fanis:BAABLgAECn8mAAIbAAkJzRXLCQDYAQAbAAkJzRXLCQDYAQAAAA==.Fatherwhig:BAAALgAECgIJAwAAAA==.',
Fe='Fenrin:BAAALgAECgQJBwAAAA==.',
Fi='Fidis:BAAALgADCgkJCwAAAA==.Fistsofdeath:BAAALgADCggJCgAAAA==.Fistychub:BAAALgADCgEJAQAAAA==.',
Fl='Flashbang:BAAALgADCgEJAQAAAA==.Flashis:BAAALgAECggJEwAAAA==.Florago:BAABLgAECn8bAAIEAAUJrgctBAB5AAAEAAUJrgctBAB5AAAAAA==.',
Fr='Frakir:BAABLgAECn87AAQXAAkJ5xlNGQCAAgAXAAkJ5xlNGQCAAgAhAAMJRwq0LQCLAAAJAAEJkAYjkwAjAAAAAA==.Fritzz:BAAALgAECgcJEgABLgAECgkJFAAFACcXAA==.Frog:BAAALgAECgIJBQAAAA==.',
Fu='Furrypaw:BAABLgAECn8uAAIgAAkJZiXLAQC8AwAgAAkJZiXLAQC8AwAAAA==.Fuzzyy:BAAALgAECgEJAQAAAA==.',
Fw='Fwapp:BAACLgAFFH8cAAIOAAgJKRtsCAA5AgAOAAgJKRtsCAA5AgAuAAQKfxcAAg4ACAlrIcgLAL8CAA4ACAlrIcgLAL8CAAAA.',
Ga='Galvanize:BAAALgAECgEJBQABLgAECgcJHAAVALoWAA==.Galynisse:BAABLgAECn8yAAMiAAgJAhjLFAA2AgAiAAgJAhjLFAA2AgASAAMJ7A4eZQCZAAAAAA==.',
Ge='Gedorah:BAABLgAECn8fAAIjAAcJOBy1AwDYAQAjAAcJOBy1AwDYAQABLgAFFAQJFQAJAGMhAA==.',
Gh='Ghaspy:BAAALgAECgUJCgAAAA==.Ghoste:BAAALgADCgMJAwAAAA==.Ghrex:BAAALgAECgEJAQAAAA==.',
Gi='Gijaick:BAABLgAECn8wAAMCAAgJWBgHRwDFAQACAAgJWBgHRwDFAQADAAEJHg4AdAAxAAAAAA==.',
Gl='Glaivethrow:BAABLgAECn8bAAIPAAkJbBZaPwDLAQAPAAkJbBZaPwDLAQAAAA==.Glizzo:BAAALgAECgYJDAAAAA==.Gloam:BAAALgADCgUJBQAAAA==.Gloomrider:BAAALgADCgUJBwAAAA==.Glueballs:BAAALgAECgEJAQABLgAECgcJDAAUAAAAAA==.',
Go='Gochujjang:BAAALgAECgYJDQAAAA==.Goldhawk:BAAALgAECggJCwAAAA==.Gosu:BAAALgAECgUJBQAAAA==.Gotchá:BAAALgAECgEJBAAAAA==.Gotwiped:BAABLgAECn8WAAIVAAgJfRqiOwASAgAVAAgJfRqiOwASAgAAAA==.',
Gr='Grimgor:BAAALgAECgcJAQAAAA==.',
Ha='Hahaheals:BAAALgAECgMJBAAAAA==.Hakhar:BAAALgADCgMJAwAAAA==.Hantaz:BAAALgAFFAEJAQAAAA==.Hanth:BAAALgADCgkJDAABLgAECgMJBAAUAAAAAA==.Hatter:BAABLgAECn8pAAQPAAgJ4xXMQgC/AQAPAAgJ4xXMQgC/AQAWAAMJ+AsRWACGAAAQAAEJNRMmKwA0AAAAAA==.',
He='Healsus:BAAALgAECgMJAwAAAA==.Heimlish:BAAALgAECgEJAQAAAA==.Hellraiser:BAABLgAECn8pAAMVAAkJORgeNwAiAgAVAAkJWhceNwAiAgAeAAcJaRNFIABRAQAAAA==.Hermione:BAAALgAECgYJDQAAAA==.Hexecution:BAAALgADCgIJAgAAAA==.',
Hi='Hiddendragon:BAAALgAECgEJAQAAAA==.',
Ho='Holydarkness:BAAALgAECgYJCwAAAA==.Holyhello:BAAALgAECgEJAQAAAA==.Holykilla:BAAALgAECgEJBQAAAA==.Holykiller:BAAALgAECgcJCgAAAA==.Hoofjob:BAAALgADCggJDgABLgAFFAUJEwAiAJofAA==.Hoplite:BAAALgAECgEJAQABLgAECggJEgAUAAAAAA==.Hotot:BAAALgADCgMJAwAAAA==.Howlly:BAABLgAECn8qAAIIAAkJExWmAgAVAgAIAAkJExWmAgAVAgAAAA==.',
Hu='Huffpuffle:BAAALgAECgUJCgAAAA==.',
['Hô']='Hôwl:BAABLgAECn8YAAIGAAcJwhBDSABuAQAGAAcJwhBDSABuAQAAAA==.',
Ic='Icdeathg:BAACLgAFFH8JAAIPAAMJ/QsRbACzAAAPAAMJ/QsRbACzAAAuAAQKfzEAAg8ACAksH2AaAHYCAA8ACAksH2AaAHYCAAAA.',
Ik='Iktaar:BAAALgAECgYJEQAAAA==.',
Il='Illidami:BAAALgADCgkJCwAAAA==.Illidamngirl:BAAALgADCgYJBgABLgAECgkJKQAMANkcAA==.',
Im='Imperius:BAACLgAFFH8VAAITAAUJHBb6SwAVAQATAAUJHBb6SwAVAQAuAAQKfyQAAhMACQmMJB0OAB0DABMACQmMJB0OAB0DAAAA.',
In='Ines:BAACLgAFFH8KAAIVAAMJWSEkhwD7AAAVAAMJWSEkhwD7AAAuAAQKfzoAAhUACQlrJHELABIDABUACQlrJHELABIDAAAA.Insomiax:BAAALgAECggJDwAAAA==.Insta:BAABLgAECn8rAAILAAcJzx3cIwA3AgALAAcJzx3cIwA3AgAAAA==.Inter:BAABLgAECn8xAAIeAAkJwSI6BAALAwAeAAkJwSI6BAALAwAAAA==.',
Ir='Iridi:BAAALgADCgEJAQAAAA==.Iritall:BAAALgADCgcJCwABLgAECgEJAgAUAAAAAA==.',
It='Ithamburglar:BAAALgAECgQJBwAAAA==.',
Iz='Izureka:BAAALgADCgYJBgAAAA==.',
Ja='Jackidaytona:BAAALgAECgcJBwAAAA==.Jakaru:BAABLgAECn8bAAIgAAkJWRqYEgCJAgAgAAkJWRqYEgCJAgAAAA==.Jankadish:BAAALgAECgcJEwAAAA==.Jarre:BAACLgAFFH8GAAIGAAQJrggsDgAFAQAGAAQJrggsDgAFAQAuAAQKfygAAgYACAmzICIKAPMCAAYACAmzICIKAPMCAAAA.Jaspirian:BAAALgADCggJFAAAAA==.Jazzil:BAAALgADCgcJCgAAAA==.',
Jb='Jbaconcheese:BAAALgAECgEJAQAAAA==.',
Je='Jehm:BAAALgAECgIJAgABLgAECgMJAwAUAAAAAA==.Jehmkin:BAAALgAECgEJAQAAAA==.Jehmothy:BAAALgAECgUJBQAAAA==.Jerome:BAAALgAECgEJAQABLgAECgEJAgAUAAAAAA==.',
Jo='Jotabop:BAAALgAECgQJBgAAAA==.',
Ju='Judgequota:BAAALgAFFAMJAwABLgAFFAUJEgAJACceAA==.Juggsgotcha:BAABLgAFFH8HAAIVAAMJexL6IADhAAAVAAMJexL6IADhAAAAAA==.Juicy:BAABLgAECn8kAAIZAAkJQRepDQBMAgAZAAkJQRepDQBMAgAAAA==.Juupiter:BAAALgAECgEJAQABLgAFFAIJBwAIAF4OAA==.',
Ka='Kabu:BAAALgAECgcJBwAAAA==.Kalia:BAABLgAECn8xAAMIAAkJxRsVPgB/AgAIAAkJxRsVPgB/AgAkAAMJUg8vDgCXAAAAAA==.Kalitra:BAAALgADCgMJAwABLgAECgkJMQAIAMUbAA==.Katatonik:BAAALgAECgUJBwAAAA==.Katharina:BAAALgAECgcJBwABLgAFFAEJAQAUAAAAAA==.Katoumae:BAACLgAFFH8TAAIlAAYJOhqrBgBCAQAlAAYJOhqrBgBCAQAuAAQKfy4ABCUACQmkI6UCAPkCACUACQk5IqUCAPkCAB8AAwm4FCYHAH4AAAUAAQlKGagMAEsAAAAA.Katoumey:BAAALgAECgYJCgABLgAFFAYJEwAlADoaAA==.',
Ke='Keratin:BAABLgAECn8uAAImAAkJvSIhBACRAgAmAAkJvSIhBACRAgAAAA==.',
Kh='Khumi:BAABLgAECn8XAAIbAAgJYSCmEgCiAgAbAAgJYSCmEgCiAgABLgAFFAkJMwATAE4mAA==.',
Ki='Kil:BAAALgADCgMJAwAAAA==.Kinan:BAABLgAECn82AAMaAAkJHSYCAgB0AwAaAAkJHSYCAgB0AwAbAAcJOx6kFwBxAgAAAA==.Kita:BAAALgAECggJEgABLgAECgkJAgAUAAAAAA==.',
Kk='Kkaarrkk:BAAALgAECgUJCAAAAA==.',
Kr='Kreloenis:BAAALgAECgIJAgAAAA==.Krindon:BAABLgAECn8pAAIWAAgJIBLTHQCNAQAWAAgJIBLTHQCNAQAAAA==.',
Ku='Kureiji:BAAALgADCgEJAQAAAA==.',
Ky='Kythin:BAAALgAECgEJAgABLgAECgkJMQAIAMUbAA==.',
La='Lacutis:BAAALgAFFAEJAQAAAA==.Lanssolo:BAABLgAECn8UAAITAAgJYga+FACLAAATAAgJYga+FACLAAAAAA==.Laww:BAAALgADCgcJCgAAAA==.',
Le='Lecroix:BAAALgADCgUJBQAAAA==.Leonus:BAAALgAECgMJAwABLgAECgIJAgAUAAAAAA==.Lessana:BAAALgAECgQJDgAAAA==.Lethalforce:BAAALgADCgMJAwAAAA==.',
Li='Liandri:BAAALgADCgEJAgAAAA==.Lightchild:BAAALgADCggJCAAAAA==.Lightkilla:BAAALgAECgEJAQAAAA==.Lightprivlge:BAAALgAECgcJDQABLgAECgcJHAAVALoWAA==.Lillith:BAAALgAECgMJAwAAAA==.Livewire:BAABLgAECn8bAAMJAAUJCyIUBAAOAQAJAAQJCyIUBAAOAQAXAAQJSxDeDQB2AAAAAA==.',
Lo='Lokohmojo:BAAALgAECgMJBAAAAA==.Lomponic:BAEBLgAECn81AAIRAAkJvR2pDwBhAgARAAkJvR2pDwBhAgAAAA==.Lonelyone:BAAALgAECgQJBQAAAA==.Loomadin:BAAALgADCgYJCQAAAA==.Loranis:BAAALgAECgQJCgAAAA==.',
Lu='Lunethra:BAABLgAECn8rAAIaAAkJwhGAKwAGAgAaAAkJwhGAKwAGAgAAAA==.',
Ma='Mageaux:BAAALgAECgEJAgAAAA==.Magerag:BAACLgAFFH8JAAIIAAMJGBtgewDgAAAIAAMJGBtgewDgAAAuAAQKfy8AAwgACQlNIn8hAJgCAAgACQlNIn8hAJgCACQAAglAGkQVAHMAAAAA.Manamontana:BAACLgAFFH8cAAMVAAgJbw6oHwD1AQAVAAcJbw6oHwD1AQAeAAEJAACgUAAAAAAuAAQKfxoAAhUACAn4H4AoAJgCABUACAn4H4AoAJgCAAAA.Marumo:BAAALgAECgMJBgAAAA==.',
Mc='Mcribz:BAACLgAFFH8gAAIVAAYJyCOdCwCJAQAVAAYJyCOdCwCJAQAuAAQKfyIAAhUACAl8IzIZAOUCABUACAl8IzIZAOUCAAAA.',
Me='Meelonusk:BAAALgAECgQJCAAAAA==.Mess:BAAALgAECgYJEAAAAA==.Messah:BAAALgAECgQJCgAAAA==.Messic:BAAALgADCgEJAQAAAA==.',
Mi='Michaelcoyle:BAACLgAFFH8PAAIaAAQJLhA8DgAsAQAaAAQJLhA8DgAsAQAuAAQKfzsAAhoACAmsIC8hAGECABoACAmsIC8hAGECAAAA.Midnightcrow:BAAALgADCgkJDwAAAA==.Mikoto:BAAALgADCgcJBwAAAA==.Milo:BAACLgAFFH8RAAILAAQJFiHkDwCGAQALAAQJFiHkDwCGAQAuAAQKfzcAAwsACQlFI3gGAPYCAAsACQlFI3gGAPYCAAoACAluHBQEALQCAAAA.Minlessu:BAAALgADCgEJAQABLgAECgEJAgAUAAAAAA==.Miorine:BAAALgAECgEJAgAAAA==.Mishra:BAAALgAECgUJBQAAAA==.Mitra:BAABLgAECn8+AAIYAAkJYiONAAA/AwAYAAkJYiONAAA/AwAAAA==.',
Mo='Moesko:BAACLgAFFH8HAAIGAAMJzQstSACXAAAGAAMJzQstSACXAAAuAAQKfxUAAgYACQlwEtc+AJYBAAYACQlwEtc+AJYBAAAA.Mof:BAAALgADCgEJAQAAAA==.Mohawkk:BAAALgAECgQJBQAAAA==.Monktup:BAAALgAECgYJCwAAAA==.Monnehbaggs:BAABLgAECn81AAMiAAkJthyyDQCSAgAiAAgJCh2yDQCSAgASAAgJpR3/DQB7AgAAAA==.Mortalidad:BAAALgADCgQJBAAAAA==.',
Mu='Muin:BAAALgAECgEJAQAAAA==.Murdersamich:BAAALgAECgQJCwAAAA==.',
My='Mybigcrits:BAAALgAECgYJDAAAAA==.Myraghor:BAAALgADCgYJBgAAAA==.',
['Mà']='Màevë:BAAALgAECgEJAgAAAA==.',
Na='Nairdax:BAAALgADCgEJAQAAAA==.Nalmec:BAABLgAECn8hAAILAAYJPQhXXgDaAAALAAYJPQhXXgDaAAAAAA==.Nama:BAAALgADCgcJFAAAAA==.Naysayre:BAABLgAECn8wAAIPAAgJ4AdSiQAOAQAPAAgJ4AdSiQAOAQAAAA==.',
Ne='Nebody:BAAALgAECgYJDwAAAA==.Necriss:BAABLgAECn8sAAITAAkJUxD4ZACmAQATAAkJUxD4ZACmAQAAAA==.Nevereven:BAAALgAECgEJAQAAAA==.',
Ni='Nightkilla:BAAALgAECgEJAwAAAA==.Nike:BAAALgAECggJEAAAAA==.Nilowin:BAABLgAECn82AAIBAAkJCxFlFwDgAQABAAkJCxFlFwDgAQAAAA==.',
No='Nokaj:BAAALgAECgEJAgAAAA==.Noshards:BAAALgAECgcJDQAAAA==.Notericdh:BAAALgAECgYJEwAAAA==.',
Og='Oghom:BAAALgADCgcJCgAAAA==.',
Oh='Ohnoitzgumby:BAABLgAECn8cAAMVAAcJuhbvbACLAQAVAAcJrBbvbACLAQAmAAMJoBJPFABOAAAAAA==.',
Om='Omiko:BAAALgAECgIJAgAAAA==.',
Op='Opeep:BAAALgADCgcJGQAAAA==.',
Or='Orah:BAAALgADCgEJAQAAAA==.',
Os='Osos:BAAALgAECgYJEAAAAA==.',
Pa='Paladimdab:BAAALgAECgQJBQAAAA==.Papachance:BAABLgAECn8cAAIIAAgJhgiSnwA8AQAIAAgJhgiSnwA8AQAAAA==.Papafrank:BAAALgAECgYJDgAAAA==.Paradis:BAAALgADCgcJBwAAAA==.Pazuzu:BAAALgADCgYJBgAAAA==.',
Pe='Peepo:BAAALgAECgEJAQAAAA==.',
Ph='Phoenixwing:BAAALgADCgYJBgAAAA==.',
Pi='Pinga:BAACLgAFFH8GAAIiAAMJjgoQNQC3AAAiAAMJjgoQNQC3AAAuAAQKfyUABCIACQkhICkFADkDACIACQkhICkFADkDABIAAgn6HOtfAFwAABEAAQmZDkSJADAAAAEuAAUUBAkJAB0AeBYA.Pinkberry:BAAALgAECgQJBAAAAA==.Pintcube:BAAALgADCgYJCAAAAA==.',
Pl='Pljeskavica:BAAALgAECgYJBwAAAA==.Plox:BAAALgAECgMJAwAAAA==.',
Po='Pookzilla:BAAALgAECgMJAwABLgAECgYJBwAUAAAAAA==.Port:BAABLgAECn8wAAIGAAkJ8R6NDAD6AgAGAAkJ8R6NDAD6AgAAAA==.Potroastjr:BAAALgAECgEJAgAAAA==.',
Pr='Preposition:BAAALgAECggJCQAAAA==.Primordus:BAAALgADCgUJBQAAAA==.Profiler:BAAALgAECgcJCgAAAA==.Protocol:BAAALgAECgMJAwAAAA==.Prïestess:BAAALgAECgcJDAAAAA==.',
Ps='Pseriph:BAABLgAECn8ZAAIDAAcJ3BZrCwAKAgADAAcJ3BZrCwAKAgAAAA==.',
Py='Pyroclastic:BAAALgAECgkJAgAAAA==.',
Ra='Radamantis:BAAALgAECgQJBwAAAA==.Raenon:BAAALgAECgEJAQAAAA==.Raggnar:BAACLgAFFH8VAAIJAAQJYyFrFQBxAQAJAAQJYyFrFQBxAQAuAAQKfzEAAgkACQmVIakHAOICAAkACQmVIakHAOICAAAA.Ragingwaters:BAAALgADCgYJCAABLgAECgIJBgAUAAAAAA==.Ranvir:BAAALgAECgYJDgAAAA==.Raun:BAABLgAECn87AAMTAAkJBiPFCQAZAwATAAkJBiPFCQAZAwAOAAMJJBEvcgCzAAAAAA==.',
Re='Reactionhank:BAAALgAECgEJAQAAAA==.Regnarr:BAAALgADCgEJAQAAAA==.Rehgar:BAAALgAFFAEJAQAAAA==.Relaire:BAABLgAECn9KAAIaAAkJTxQHMwAQAgAaAAkJTxQHMwAQAgAAAA==.Remenissions:BAAALgAECgEJAQAAAA==.Resonate:BAAALgAFFAIJAwAAAA==.',
Ri='Rikane:BAAALgADCgcJDAABLgADCgcJEgAUAAAAAA==.Rikenji:BAAALgAECgEJAQABLgAFFAIJBwAIAF4OAA==.Riku:BAABLgAECn82AAIlAAkJvSDSAgDzAgAlAAkJvSDSAgDzAgAAAA==.Ritehand:BAAALgAECgEJAgAAAA==.',
Ro='Rock:BAAALgAECgcJEgAAAA==.Rocks:BAAALgAECgEJAQAAAA==.Rockyrag:BAAALgAECgUJBQAAAA==.Roguey:BAABLgAECn8sAAMnAAkJuQ9KDABoAQAnAAcJlBFKDABoAQABAAcJ/wxIKQBNAQAAAA==.Roots:BAAALgAECgEJCAAAAA==.',
Ru='Rulethrefour:BAAALgAECgQJCAABLgAECgcJHAAVALoWAA==.',
Ry='Ryveri:BAABLgAECn8nAAILAAkJ0hnFHQAAAgALAAkJ0hnFHQAAAgAAAA==.',
Sa='Sablehide:BAABLgAECn81AAIHAAkJ4BnrEQBUAgAHAAkJ4BnrEQBUAgAAAA==.Sanaron:BAAALgADCgIJAgAAAA==.Sanaty:BAAALgAFFAIJBAAAAA==.Sarnak:BAAALgADCgMJAwAAAA==.Saryn:BAAALgAECgYJEwAAAA==.Satanz:BAAALgADCgIJAgAAAA==.Sathanus:BAABLgAECn8VAAIPAAUJcAytuQC4AAAPAAUJbwytuQC4AAAAAA==.Sathir:BAAALgADCgMJAwAAAA==.',
Se='Searate:BAAALgADCgcJEgAAAA==.Seaside:BAACLgAFFH8PAAIVAAMJ/iX3HAAvAQAVAAMJ/iX3HAAvAQAuAAQKfxgAAxUABwk9JfZEAPMBABUABwk9JfZEAPMBAB4AAgmEC+8/AE4AAAAA.Secrett:BAABLgAECn8gAAMBAAcJkhW0AgAeAQABAAcJkhW0AgAeAQAnAAEJew5gKQAwAAAAAA==.Sephyxia:BAABLgAECn8vAAIeAAkJdBqmDgAhAgAeAAkJdBqmDgAhAgAAAA==.Serryon:BAAALgADCgIJAgAAAA==.',
Sf='Sfora:BAAALgAECgUJBQAAAA==.',
Sh='Shadowreaper:BAAALgADCgYJBQAAAA==.Shadowwzz:BAAALgADCgEJAQAAAA==.Shocknezz:BAAALgAECgYJCAAAAA==.Shockwaves:BAAALgAECgEJAQAAAA==.Shoçknezz:BAAALgAECgMJBQAAAA==.',
Si='Silverwolf:BAABLgAECn9GAAIhAAkJ/SC1AgDrAgAhAAkJ/SC1AgDrAgAAAA==.Simplyunlock:BAACLgAFFH8gAAMCAAUJtwwJGQDIAAACAAQJtwwJGQDIAAAEAAEJAADaMQAAAAAuAAQKfycAAwIACQnzE4g0AAcCAAIACQnzE4g0AAcCAAMAAgnnBZVmAEMAAAAA.Simplyvoided:BAAALgAECgQJBgAAAA==.Sinfulcynic:BAAALgADCgQJBQAAAA==.Sinverguenza:BAAALgAECgMJBQAAAA==.Sizzlechop:BAABLgAECn8uAAMVAAkJ/g+piABTAQAVAAgJ7QqpiABTAQAeAAMJrBYfNQDDAAAAAA==.',
Sk='Skizzak:BAAALgADCgQJBAABLgAFFAYJIAAVAMgjAA==.Skweeks:BAAALgAECgMJBAAAAA==.',
Sm='Smelvin:BAABLgAECn8cAAIJAAkJ8xlaHQD2AQAJAAkJ8xlaHQD2AQABLgAECgQJCAAUAAAAAA==.Smoko:BAAALgAECgIJAgABLgAECgUJBQAUAAAAAA==.',
Sn='Snailslolol:BAAALgAFFAMJAwAAAA==.Snakey:BAECLgAFFH8bAAMHAAUJGgmNPADVAAAHAAQJGgmNPADVAAAcAAIJ1wJTEAA5AAAuAAQKfywAAwcACAmLGD4aAPkBAAcACAmLGD4aAPkBABwABgl5BHkmAO8AAAAA.',
So='Solara:BAABLgAECn8hAAQRAAkJMRhAFwAPAgARAAkJMRhAFwAPAgASAAEJQAIShwApAAAiAAEJXgKYXgAkAAAAAA==.Soleill:BAAALgAECgcJBwAAAA==.Sondan:BAAALgADCgMJAwAAAA==.Songs:BAAALgAECgEJAQABLgAECgYJGAANAP8gAA==.',
Sp='Spellpowa:BAAALgAECgYJDgAAAA==.',
Sq='Squirtin:BAAALgAECgIJAgAAAA==.',
Ss='Ssminion:BAAALgAECgMJBgAAAA==.',
St='Stalath:BAAALgAECgUJCQAAAA==.Stormwing:BAABLgAECn8fAAMJAAgJiBmvJgC2AQAJAAgJiBmvJgC2AQAXAAEJMRY+zABAAAAAAA==.Strecagosa:BAAALgAECgYJDQAAAA==.',
Su='Sumarr:BAAALgAECgcJDAAAAA==.',
Sv='Svenn:BAAALgAECgYJCAAAAA==.',
Sw='Swiftstrike:BAAALgAECgMJAwAAAA==.',
Sy='Sybelissa:BAAALgAECgMJAwABLgAECgcJCgAUAAAAAA==.Synni:BAAALgADCgEJAQAAAA==.',
['Sÿ']='Sÿnÿster:BAAALgAECgQJBQABLgAFFAUJFAAaAI4cAA==.',
Ta='Talron:BAAALgAECgYJDQAAAA==.Tastytay:BAAALgADCgMJAwAAAA==.Tatertots:BAABLgAECn8yAAMmAAkJFCCxAgDYAgAmAAkJFCCxAgDYAgAVAAMJ8hON7ACmAAAAAA==.',
Te='Tea:BAABLgAECn8xAAIaAAkJgCXgAwBTAwAaAAkJgCXgAwBTAwAAAA==.Teal:BAAALgAECgMJAwAAAA==.Templyn:BAACLgAFFH8FAAIVAAMJlAKEUQBOAAAVAAMJlAKEUQBOAAAuAAQKfzUAAxUACQllFLhWAMEBABUACQmMDrhWAMEBAB4ACAkJFm0aAIoBAAAA.Templÿn:BAAALgAECgQJBAABLgAFFAMJBQAVAJQCAA==.Tenebrarum:BAABLgAECn8bAAIaAAgJGQ0xVwBjAQAaAAgJGQ0xVwBjAQAAAA==.Testorooni:BAABLgAECn8ZAAIaAAcJkBgpMwDjAQAaAAcJkBgpMwDjAQAAAA==.',
Th='Thakodi:BAAALgAECgQJBAAAAA==.Thannos:BAAALgADCgEJAQAAAA==.Tharvan:BAAALgADCgcJDAAAAA==.Thavok:BAAALgAECgEJAQAAAA==.Thedeadman:BAABLgAECn8kAAIVAAkJEyIrJAB0AgAVAAkJEyIrJAB0AgAAAA==.Thepriestg:BAAALgAECgEJAQAAAA==.Thiccksilver:BAAALgADCgcJBwABLgAFFAQJDwACAAUWAA==.Thompson:BAABLgAECn8VAAIVAAcJuxTvkwA/AQAVAAcJuxTvkwA/AQAAAA==.Thunderflaps:BAAALgAECgUJCQAAAA==.Thyrus:BAACLgAFFH8JAAIdAAQJeBYLFwAlAQAdAAQJeBYLFwAlAQAuAAQKfzUAAx0ACQk9Io0DAAwDAB0ACQk9Io0DAAwDABwAAQmqAvtEACMAAAAA.',
Ti='Tirna:BAABLgAECn84AAIjAAkJng5yBACtAQAjAAkJng5yBACtAQAAAA==.',
To='Toebot:BAAALgAECgEJAQAAAA==.Toggle:BAAALgAECgEJAQAAAA==.Tomsellock:BAABLgAECn8WAAMEAAcJjhBuBwDcAQAEAAcJjhBuBwDcAQACAAEJugM+LAEmAAAAAA==.Tonari:BAAALgAECgEJAQABLgAECgYJEAAUAAAAAA==.Torvi:BAAALgADCgMJAwAAAA==.',
Tr='Transmørtuus:BAAALgAECgQJCQAAAA==.Treehug:BAAALgAECggJEwAAAA==.Triple:BAAALgAECgQJBwABLgAECgYJEAAUAAAAAA==.Trolleonne:BAAALgAECgIJAgAAAA==.',
Tu='Tullen:BAEBLgAECn81AAISAAkJjRGKIgCuAQASAAkJjRGKIgCuAQAAAA==.Turanos:BAABLgAECn8bAAIoAAUJtA6zBACTAAAoAAUJtA6zBACTAAAAAA==.',
Tw='Tweyen:BAAALgAECgEJAQAAAA==.Twistedbael:BAAALgAECgUJBQAAAA==.',
Ty='Tyindaris:BAAALgAECgQJCgAAAA==.Tyloregeth:BAABLgAECn8sAAIRAAgJphSEKQCFAQARAAgJphSEKQCFAQAAAA==.',
['Tè']='Tèmplyn:BAAALgADCgEJAQABLgAFFAMJBQAVAJQCAA==.',
['Té']='Témplýn:BAAALgADCgEJAQABLgAFFAMJBQAVAJQCAA==.',
['Të']='Tëmplýn:BAAALgAECgQJBQABLgAFFAMJBQAVAJQCAA==.',
Ul='Ulfrunn:BAAALgADCgYJBgAAAA==.Ultrachad:BAACLgAFFH8kAAIVAAgJYxnXDwBeAgAVAAgJYxnXDwBeAgAuAAQKfx4AAhUACAlNIwUUAAMDABUACAlNIwUUAAMDAAAA.',
Um='Umami:BAABLgAECn8gAAILAAYJ+RhzSgB7AQALAAYJ+RhzSgB7AQAAAA==.',
Un='Unggoy:BAACLgAFFH8tAAQaAAkJHR/yAwDjAQAbAAgJnR38AgAkAgAaAAYJ3hryAwDjAQAZAAQJyRQAEgA4AQAuAAQKfygAAxsACQkhJrsBAKYDABsACQkhJrsBAKYDABoAAQnFJfX0AGsAAAAA.Unhollowed:BAAALgAECgIJBAAAAA==.Unholywaters:BAAALgAECgIJBgAAAA==.',
Ur='Urianna:BAAALgAECgYJCwAAAA==.',
Va='Vaelthirion:BAABLgAECn8nAAIIAAgJYxbETwDsAQAIAAgJYxbETwDsAQAAAA==.Vahidamus:BAAALgAECgkJEAAAAA==.Valkaryon:BAAALgAECgcJCgABLgAFFAIJAwAUAAAAAA==.Valmirax:BAAALgADCggJEgAAAA==.Valton:BAABLgAECn9cAAITAAgJphJraACeAQATAAgJphJraACeAQAAAA==.',
Ve='Vegetation:BAAALgAECgQJBwAAAA==.Velenestus:BAAALgAECgMJBgAAAA==.Verses:BAAALgADCgUJBQAAAA==.',
Vi='Vizsla:BAAALgAECgEJAQAAAA==.',
Wa='Wackaman:BAABLgAECn8pAAIMAAkJ2RxfCQBfAgAMAAkJ2RxfCQBfAgAAAA==.Waffleshirt:BAAALgAFFAEJAQAAAA==.Warpig:BAAALgAECgYJEQAAAA==.Wasps:BAAALgAECgYJEQAAAA==.',
We='Wegmaniac:BAAALgADCgYJCAAAAA==.Welastrexa:BAAALgADCgUJBQABLgAECgIJBgAUAAAAAA==.',
Wi='Wickedclöwn:BAAALgADCgMJAwAAAA==.Winchester:BAAALgADCgIJAgAAAA==.Windhorn:BAABLgAECn8lAAIbAAcJCgmKAQDnAAAbAAcJCgmKAQDnAAAAAA==.Winds:BAABLgAECn8YAAINAAYJ/yBoFwAqAgANAAYJ/yBoFwAqAgAAAA==.',
Wn='Wntrizcoming:BAAALgADCgMJBQAAAA==.',
Wo='Wolfquota:BAACLgAFFH8SAAIJAAUJJx4QHwAmAQAJAAUJJx4QHwAmAQAuAAQKfyQAAwkACAmCIkkJAP4CAAkACAmCIkkJAP4CACEABAntE08eAOkAAAAA.Wolftime:BAAALgADCgUJBQAAAA==.Wombaa:BAACLgAFFH8ZAAMVAAUJoiXoNACWAQAVAAUJoiXoNACWAQAmAAIJPR77GgCxAAAuAAQKfxwAAhUACAleJGEKAEgDABUACAleJGEKAEgDAAAA.Woolybully:BAAALgAECgEJAQABLgAECgYJBwAUAAAAAA==.',
Wr='Wrathbolt:BAAALgAFFAIJAgABLgAFFAQJDwASALsVAA==.Wrathmo:BAACLgAFFH8LAAMNAAQJoRrDEQAuAQANAAQJoRrDEQAuAQApAAIJ1wu5DQCDAAAuAAQKfyUAAw0ACAljHG8UABcCAA0ABwlpHm8UABcCACkABwkdCqdAAPgAAAEuAAUUBAkPABIAuxUA.Wrathp:BAABLgAFFH8PAAISAAQJuxXaFgAHAQASAAQJuxXaFgAHAQAAAA==.Wrolie:BAAALgADCgMJAwAAAA==.',
['Wê']='Wêêdyys:BAAALgADCgMJBAAAAA==.',
Xy='Xyr:BAEALgAECgEJAQAAAA==.',
Ya='Yamiamigo:BAAALgAECgEJAwAAAA==.',
Yo='Yonah:BAAALgAECgEJAQAAAA==.Yougotsniped:BAAALgADCgEJAQAAAA==.',
Za='Zakos:BAAALgAECgcJCgAAAA==.Zandalia:BAAALgAECgMJAwAAAA==.Zark:BAEALgAECgEJAQABLgAECgkJGQAXAHsWAA==.Zarrallice:BAAALgADCgEJAQAAAA==.',
Ze='Zemphoths:BAAALgAECgcJCgAAAA==.Zephyra:BAAALgADCgEJAQABLgAECgUJBQAUAAAAAA==.',
Zo='Zoa:BAAALgADCgYJBgAAAA==.Zolton:BAAALgADCgMJAwAAAA==.Zornak:BAABLgAECn8hAAICAAYJsw6VBwDnAAACAAYJsw6VBwDnAAAAAA==.',
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
