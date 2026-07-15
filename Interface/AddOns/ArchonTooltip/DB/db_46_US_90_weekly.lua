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

local lookup = {'Rogue-Subtlety','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Balance','Druid-Restoration','Evoker-Augmentation','Mage-Frost','Shaman-Elemental','Warrior-Arms','Warrior-Fury','Warrior-Protection','Monk-Windwalker','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Shadow','Priest-Holy','Paladin-Retribution','Monk-Brewmaster','Unknown-Unknown','DeathKnight-Unholy','DemonHunter-Havoc','Shaman-Restoration','Rogue-Outlaw','Hunter-Survival','Hunter-BeastMastery','Priest-Discipline','Hunter-Marksmanship','Evoker-Devastation','Evoker-Preservation','DeathKnight-Blood','Druid-Guardian','Monk-Mistweaver','Shaman-Enhancement','Mage-Fire','Mage-Arcane','Druid-Feral','DeathKnight-Frost','Rogue-Assassination','Paladin-Protection',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=46,date='2026-07-12',data={Aa='Aamon:BAAALgAECgQJCgAAAA==.',
Ab='Abacus:BAABLgAECn8jAAIBAAkJjyLACwBoAgABAAkJjyLACwBoAgAAAA==.',
Ac='Acin:BAAALgADCgQJBAAAAA==.',
Ad='Adam:BAACLgAFFH8mAAQCAAkJSRtqEQB1AQACAAcJ0RtqEQB1AQADAAMJlBFcDQCiAAAEAAEJECatEwBvAAAuAAQKfy4ABAIACQk2JF4WAM4CAAIACQmcI14WAM4CAAMABQljJKcNAOsBAAQAAQkaI5QvAGAAAAAA.Adedruid:BAABLgAECn8gAAMFAAYJdR9cKwCnAQAFAAYJdR9cKwCnAQAGAAYJ3xoBSgB6AQAAAA==.Adevoker:BAAALgAECgQJBAAAAA==.Adragon:BAABLgAECn8rAAIHAAkJ5RpLDwByAgAHAAkJ5RpLDwByAgAAAA==.',
Ae='Aengyl:BAAALgAECgQJBAAAAA==.Aeonne:BAABLgAECn8WAAIIAAgJyxLYkQBUAQAIAAgJyxLYkQBUAQAAAA==.',
Ak='Akshul:BAABLgAECn8UAAIJAAYJ5Q1HRgAvAQAJAAYJ5Q1HRgAvAQAAAA==.Akurama:BAAALgAECgcJCgAAAA==.',
Al='Alannon:BAAALgADCgUJBQAAAA==.Aldrea:BAAALgAECggJEgAAAA==.Allsmiles:BAABLgAECn8VAAQKAAkJZh7tCAAhAgAKAAgJhRrtCAAhAgALAAUJChm2TQBwAQAMAAQJkh4oKgDvAAAAAA==.Allura:BAAALgAECgUJEAAAAA==.Alorian:BAAALgAECgIJAgAAAA==.Alttharius:BAAALgAECgMJAwABLgAECgkJHAANAGMhAA==.Alyysha:BAABLgAECn8bAAIOAAcJlwkCRgBgAQAOAAcJlwkCRgBgAQAAAA==.',
Am='Amoon:BAABLgAECn81AAMPAAkJgBmXKAAoAgAPAAkJ0ReXKAAoAgAQAAYJBRXYEgAjAQAAAA==.',
An='Angelrain:BAABLgAECn8sAAMRAAgJWByRDgCaAgARAAgJWByRDgCaAgASAAcJ8QcGPAAFAQAAAA==.Aniata:BAAALgAECgEJAQAAAA==.',
Ar='Archymedes:BAABLgAECn8sAAILAAcJJxFLPgBMAQALAAcJJxFLPgBMAQAAAA==.Arckady:BAABLgAECn8ZAAITAAQJKR7+CgBdAQATAAQJKR7+CgBdAQAAAA==.Areko:BAAALgAECgIJBQAAAA==.Aresh:BAAALgAECgEJAgAAAA==.Array:BAAALgAECggJEgABLgAECgkJMAAGAPEeAA==.Artharius:BAABLgAECn8cAAMNAAkJYyGpFQALAgANAAkJYyGpFQALAgAUAAEJohCkDQBDAAAAAA==.',
As='Asanad:BAAALgADCgUJBQABLgAECgYJDQAVAAAAAA==.',
Au='Auburnbeard:BAAALgADCgYJBgAAAA==.Aumed:BAAALgADCgEJAQAAAA==.Aurelionburn:BAAALgAECgEJAgAAAA==.',
Av='Averle:BAABLgAECn99AAIDAAcJuA86AwAPAQADAAcJuA86AwAPAQAAAA==.',
Ay='Ayahuascero:BAAALgAECgEJAQAAAA==.',
Az='Azrran:BAAALgADCgEJAQAAAA==.Aztharot:BAAALgAECgIJBAAAAA==.',
Ba='Badchoices:BAAALgAECgQJBAAAAA==.Badkittie:BAAALgAECgQJEgAAAA==.Balding:BAAALgAECgQJCAAAAA==.Baphico:BAAALgADCgUJCQAAAA==.',
Be='Bearhug:BAAALgAECgEJAQAAAA==.Beefsnake:BAEALgAFFAEJAQABLgAFFAUJGwAHABoJAA==.Behemoth:BAAALgAECgQJBAAAAA==.Belinda:BAAALgAECgEJAQABLgAFFAgJIwAWABMeAA==.Bettyßaraxus:BAAALgAECgMJAwABLgAECgkJMgATAK8fAA==.Bettyßlight:BAABLgAECn8XAAIWAAgJxxrBAwAnAgAWAAgJxxrBAwAnAgABLgAECgkJMgATAK8fAA==.Bewater:BAAALgADCgcJBwAAAA==.',
Bi='Bigcarol:BAAALgAECgEJAQAAAA==.Bigunsforu:BAAALgAECgYJEAAAAA==.',
Bl='Bladesmcgee:BAAALgAECggJCQABLgAECgQJCAAVAAAAAA==.Blasphem:BAAALgADCgQJBAAAAA==.',
Bo='Bobadelphia:BAAALgADCgYJBgABLgAECgYJEQAVAAAAAA==.Bofahdeez:BAABLgAECn8aAAMSAAgJfA6+PABHAQASAAcJWA6+PABHAQARAAcJLQwIPgAZAQAAAA==.Bogs:BAACLgAFFH8bAAIIAAUJmx2SIAAuAQAIAAUJmx2SIAAuAQAuAAQKfyMAAggACAnrIb4jAOQCAAgACAnrIb4jAOQCAAAA.Bolomorte:BAAALgAECgEJAQAAAA==.Bonedaddy:BAAALgAECgYJBgAAAA==.Boomstick:BAAALgAFFAEJAQABLgAFFAUJEgAPAB8OAA==.',
Br='Brewswayne:BAAALgADCgQJBAABLgAFFAIJAwAVAAAAAA==.Brolic:BAABLgAECn87AAMXAAkJuyEEBAAOAwAXAAkJuyEEBAAOAwAPAAEJJgnfKQEkAAAAAA==.',
['Bä']='Bämboo:BAAALgAFFAEJAgABLgAFFAUJDAAYACsVAA==.',
Ca='Cail:BAEBLgAECn8ZAAIYAAkJexYhIABPAgAYAAkJexYhIABPAgAAAA==.Calamìty:BAAALgADCgcJDgABLgAFFAQJCwAGANAJAA==.Calisa:BAABLgAECn87AAIZAAkJ6h9nAQDnAgAZAAkJ6h9nAQDnAgAAAA==.Cardio:BAAALgAECgUJBgAAAA==.Carnifexx:BAABLgAFFH8GAAMYAAIJqxQfZAB/AAAYAAIJqxQfZAB/AAAJAAIJggmtSABtAAABLgAFFAIJBgAYAKsUAA==.Cassey:BAAALgAECgEJAQAAAA==.',
Ce='Celesteus:BAAALgADCgkJFAAAAA==.',
Ch='Charis:BAAALgAECgYJCwAAAA==.Chel:BAAALgAECgEJAQAAAA==.Chigutotems:BAAALgAECgYJCwABLgAECgkJGwAPAGwWAA==.Chimmoku:BAABLgAFFH8IAAIBAAQJ6RA/HAA6AQABAAQJ6RA/HAA6AQABLgAFFAkJMAABAKMZAA==.Choi:BAAALgAECgUJDwAAAA==.Chooq:BAAALgADCgIJAgAAAA==.Chozen:BAAALgAECgUJEAAAAA==.Chumlee:BAAALgAECgYJDgAAAA==.',
Ci='Cienna:BAAALgAECgYJDgAAAA==.Cigz:BAAALgADCgEJAQAAAA==.Cinch:BAAALgAECgIJAgAAAA==.',
Co='Colinferral:BAAALgAECgYJCAAAAA==.Coulee:BAAALgAECgQJCAABLgAFFAMJCAAXAGkgAA==.Cowladin:BAAALgADCgUJBQAAAA==.',
Cr='Crakzkull:BAAALgAECgUJCwAAAA==.Croar:BAAALgAECgMJBAAAAA==.Cronicpain:BAAALgADCgkJCQAAAA==.',
Cu='Cuernuda:BAAALgAECgEJAQAAAA==.',
['Cä']='Cäntstandya:BAACLgAFFH8RAAMaAAQJVRjeGwDyAAAaAAMJnxfeGwDyAAAbAAMJmRiVZQDaAAAuAAQKfyMAAxsACAkvG1cSAKUCABsACAliGVcSAKUCABoABwkaHjsTAA0CAAAA.',
Da='Daiko:BAAALgAECgcJCwABLgAECgkJNQAcALYcAA==.Daks:BAAALgAFFAIJAwAAAA==.Dargo:BAAALgAECgYJEwAAAA==.Darklucrezia:BAACLgAFFH8XAAMbAAUJkRwyFgA+AQAbAAUJkRwyFgA+AQAdAAIJNgLRNQBIAAAuAAQKfy4AAxsACAn3H0QeAHACABsACAltH0QeAHACAB0ACAkOEeQlAPoBAAAA.Darkpyro:BAAALgAECgIJAgAAAA==.Dazzlefraz:BAAALgAECgQJBAAAAA==.',
De='Demonklunter:BAAALgADCgYJEAAAAA==.Denaida:BAAALgAECgIJAgAAAA==.Destructoid:BAAALgAECgEJAQAAAA==.',
Dg='Dgk:BAAALgAECgcJBwABLgAECgcJDAAVAAAAAA==.',
Dh='Dh:BAAALgAECgMJAwAAAA==.',
Di='Dicey:BAAALgADCgMJAwABLgAECgQJBwAVAAAAAA==.Dinkler:BAAALgAECgcJBwAAAA==.',
Do='Dochunter:BAAALgAECgUJBQAAAA==.',
Dr='Dracarius:BAABLgAECn8fAAQeAAUJBhmOAQAkAQAeAAQJBhmOAQAkAQAHAAMJIwvCdQB7AAAfAAIJAARZCwAcAAAAAA==.Drega:BAAALgAECgYJBwAAAA==.Droods:BAAALgAECgQJBQAAAA==.Drtypinkcake:BAABLgAECn8iAAIXAAkJ9wnbJABRAQAXAAkJ9wnbJABRAQAAAA==.Druskgar:BAABLgAECn8qAAMWAAkJMx8sMAA+AgAWAAkJMx8sMAA+AgAgAAcJ4A8sIwA5AQAAAA==.Dryad:BAABLgAECn8eAAIhAAUJMhDDCAC+AAAhAAUJMhDDCAC+AAAAAA==.',
Du='Duckster:BAAALgADCgYJBwAAAA==.Dunce:BAACLgAFFH8HAAIiAAIJdR+sPQCuAAAiAAIJdR+sPQCuAAAuAAQKfygAAiIACAnyIJsNAMMCACIACAnyIJsNAMMCAAAA.Durkk:BAABLgAECn87AAIgAAkJ9yFxBQDSAgAgAAkJ9yFxBQDSAgAAAA==.Durza:BAAALgAECgcJEAAAAA==.',
['Dä']='Dännydevito:BAAALgADCgQJBAAAAA==.',
Ea='Easyheal:BAAALgAECgUJCwAAAA==.',
Ed='Eduard:BAAALgAECgYJCQAAAA==.',
Eg='Egon:BAAALgAECgQJBAABLgAFFAIJBwAIAF4OAA==.',
Ek='Eklipse:BAAALgAECgMJAwAAAA==.',
El='Elanthae:BAAALgAECgQJEQAAAA==.Elysia:BAAALgAECgEJAgAAAA==.',
Er='Erzulie:BAAALgAECgUJBAAAAA==.',
Es='Estara:BAABLgAECn81AAIhAAkJqwtbJgAhAQAhAAkJqwtbJgAhAQAAAA==.',
Et='Etali:BAABLgAECn8yAAILAAkJQBwJEQBuAgALAAkJQBwJEQBuAgAAAA==.',
Ex='Expired:BAAALgAECgEJAQAAAA==.',
Fa='Faite:BAAALgADCgUJBQAAAA==.Falorin:BAACLgAFFH8HAAIIAAIJXg5HogCKAAAIAAIJXg5HogCKAAAuAAQKfyEAAggACQmzFZNjALcBAAgACQmzFZNjALcBAAAA.Fanis:BAABLgAECn8mAAIdAAkJzRXLCQDYAQAdAAkJzRXLCQDYAQAAAA==.Fatherwhig:BAAALgAECgIJAwAAAA==.',
Fe='Fenrin:BAAALgAECgQJBwAAAA==.',
Fi='Fidis:BAAALgADCgkJCwAAAA==.Fistsofdeath:BAAALgADCggJCgAAAA==.Fistychub:BAAALgADCgEJAQAAAA==.',
Fl='Flashbang:BAAALgADCgEJAQAAAA==.Flashis:BAAALgAECggJEwAAAA==.Florago:BAABLgAECn8fAAIEAAUJCAkrBgCmAAAEAAUJCAkrBgCmAAAAAA==.',
Fr='Frakir:BAABLgAECn87AAQYAAkJ5xlNGQCAAgAYAAkJ5xlNGQCAAgAjAAMJRwq0LQCLAAAJAAEJkAYjkwAjAAAAAA==.Fritzz:BAAALgAECgcJEgABLgAECgkJFAAFACcXAA==.Frog:BAAALgAECgIJBQAAAA==.',
Fu='Furrypaw:BAABLgAECn8uAAIiAAkJZiXLAQC8AwAiAAkJZiXLAQC8AwAAAA==.Fuzzyy:BAAALgAECgEJAQAAAA==.',
Fw='Fwapp:BAACLgAFFH8cAAIOAAgJKRtsCAA5AgAOAAgJKRtsCAA5AgAuAAQKfxcAAg4ACAlrIcgLAL8CAA4ACAlrIcgLAL8CAAAA.',
Ga='Galvanize:BAAALgAECgEJBQABLgAECgcJHAAWALoWAA==.Galynisse:BAABLgAECn8yAAMcAAgJAhjLFAA2AgAcAAgJAhjLFAA2AgASAAMJ7A4eZQCZAAAAAA==.',
Ge='Gedorah:BAABLgAECn8fAAIkAAcJOBy1AwDYAQAkAAcJOBy1AwDYAQABLgAFFAQJFwAJAAwiAA==.',
Gh='Ghaspy:BAAALgAECgUJCgAAAA==.Ghoste:BAAALgADCgMJAwAAAA==.Ghrex:BAAALgAECgEJAQAAAA==.',
Gi='Gijaick:BAABLgAECn8wAAMCAAgJWBgHRwDFAQACAAgJWBgHRwDFAQADAAEJHg4AdAAxAAAAAA==.',
Gl='Glaivethrow:BAABLgAECn8bAAIPAAkJbBZaPwDLAQAPAAkJbBZaPwDLAQAAAA==.Glizzo:BAAALgAECgYJDAAAAA==.Gloam:BAAALgADCgUJBQAAAA==.Gloomrider:BAAALgADCgUJBwAAAA==.Glueballs:BAAALgAECgEJAQABLgAECgcJDAAVAAAAAA==.',
Go='Gochujjang:BAAALgAECgYJDQAAAA==.Goldhawk:BAAALgAECggJDAAAAA==.Gosu:BAAALgAECgUJBQAAAA==.Gotchá:BAAALgAECgEJBAAAAA==.Gotwiped:BAABLgAECn8WAAIWAAgJfRqiOwASAgAWAAgJfRqiOwASAgAAAA==.',
Gr='Grexx:BAAALgAECgUJBAABLgAECgkJNQAcALYcAA==.Grimgor:BAAALgAECgcJAQAAAA==.',
Ha='Hahaheals:BAAALgAECgMJBAAAAA==.Hakhar:BAAALgADCgMJAwAAAA==.Hantaz:BAAALgAFFAEJAQAAAA==.Hanth:BAAALgADCgkJDAABLgAECgMJBAAVAAAAAA==.Hatter:BAABLgAECn8pAAQPAAgJ4xXMQgC/AQAPAAgJ4xXMQgC/AQAXAAMJ+AsRWACGAAAQAAEJNRMmKwA0AAAAAA==.',
He='Healsus:BAAALgAECgMJAwAAAA==.Heimlish:BAAALgAECgEJAQAAAA==.Hellraiser:BAABLgAECn8pAAMWAAkJORgeNwAiAgAWAAkJWhceNwAiAgAgAAcJaRNFIABRAQAAAA==.Hermione:BAAALgAECgYJDQAAAA==.Hexecution:BAAALgADCgIJAgAAAA==.',
Hi='Hiddendragon:BAAALgAECgEJAQAAAA==.',
Ho='Holydarkness:BAAALgAECgYJCwAAAA==.Holyhello:BAAALgAECgEJAQAAAA==.Holykilla:BAAALgAECgEJBQAAAA==.Holykiller:BAAALgAECgcJCgAAAA==.Hoofjob:BAAALgADCggJDgABLgAFFAUJEwAcAJofAA==.Hoplite:BAAALgAECgEJAQABLgAECggJEgAVAAAAAA==.Hotot:BAAALgADCgMJAwAAAA==.Howlly:BAABLgAECn88AAIIAAkJwBYQBAA4AgAIAAkJwBYQBAA4AgAAAA==.',
Hu='Huffpuffle:BAAALgAECgUJCgAAAA==.',
['Hô']='Hôwl:BAABLgAECn8YAAIGAAcJwhBDSABuAQAGAAcJwhBDSABuAQAAAA==.',
Ic='Icdeathg:BAACLgAFFH8JAAIPAAMJ/QsRbACzAAAPAAMJ/QsRbACzAAAuAAQKfzEAAg8ACAksH2AaAHYCAA8ACAksH2AaAHYCAAAA.',
Ik='Iktaar:BAAALgAECgYJEQAAAA==.',
Il='Illidami:BAAALgADCgkJCwAAAA==.Illidamngirl:BAAALgADCgYJBgABLgAECgkJLgAMAN4fAA==.',
Im='Imperius:BAACLgAFFH8VAAITAAUJHBb6SwAVAQATAAUJHBb6SwAVAQAuAAQKfyQAAhMACQmMJB0OAB0DABMACQmMJB0OAB0DAAAA.',
In='Ines:BAACLgAFFH8KAAIWAAMJWSEkhwD7AAAWAAMJWSEkhwD7AAAuAAQKfzoAAhYACQlrJHELABIDABYACQlrJHELABIDAAAA.Insomiax:BAAALgAECggJDwAAAA==.Insta:BAABLgAECn8rAAILAAcJzx3cIwA3AgALAAcJzx3cIwA3AgAAAA==.Inter:BAABLgAECn8xAAIgAAkJwCI6BAALAwAgAAkJwCI6BAALAwAAAA==.',
Ir='Iridi:BAAALgADCgEJAQAAAA==.Iritall:BAAALgADCgcJCwABLgAECgEJAgAVAAAAAA==.',
It='Ithamburglar:BAAALgAECgQJBwAAAA==.',
Iz='Izureka:BAAALgADCgYJBgAAAA==.',
Ja='Jackidaytona:BAAALgAECgcJBwAAAA==.Jakaru:BAABLgAECn8bAAIiAAkJWRqYEgCJAgAiAAkJWRqYEgCJAgAAAA==.Jankadish:BAAALgAECgcJEwAAAA==.Jarre:BAACLgAFFH8GAAIGAAQJrggsDgAFAQAGAAQJrggsDgAFAQAuAAQKfygAAgYACAmzICIKAPMCAAYACAmzICIKAPMCAAAA.Jaspirian:BAAALgADCggJFAAAAA==.Jazzil:BAAALgADCgcJCgAAAA==.',
Jb='Jbaconcheese:BAAALgAECgEJAQAAAA==.',
Je='Jehm:BAAALgAECgIJAgABLgAECgMJAwAVAAAAAA==.Jehmkin:BAAALgAECgEJAQAAAA==.Jehmothy:BAAALgAECgUJBQAAAA==.Jerome:BAAALgAECgEJAQABLgAECgEJAgAVAAAAAA==.',
Jo='Jotabop:BAAALgAECgQJBgAAAA==.',
Ju='Judgequota:BAAALgAFFAMJAwABLgAFFAUJFQAJAGMfAA==.Juggsgotcha:BAABLgAFFH8HAAIWAAMJexJOOADaAAAWAAMJexJOOADaAAAAAA==.Juicy:BAABLgAECn8kAAIaAAkJQRepDQBMAgAaAAkJQRepDQBMAgAAAA==.Juupiter:BAAALgAECgEJAQABLgAFFAIJBwAIAF4OAA==.',
Ka='Kabu:BAAALgAECgcJBwAAAA==.Kagor:BAAALgAECgQJBAAAAA==.Kalia:BAABLgAECn8xAAMIAAkJwxsVPgB/AgAIAAkJwxsVPgB/AgAlAAMJUg8vDgCXAAAAAA==.Kalitra:BAAALgADCgMJAwABLgAECgkJMQAIAMMbAA==.Kardaz:BAAALgAECgQJBQABLgAECggJcAATAGsYAA==.Katatonik:BAAALgAECgUJCAAAAA==.Katharina:BAAALgAECgcJBwABLgAFFAEJAQAVAAAAAA==.Katoumae:BAACLgAFFH8WAAImAAcJvBrWAQBTAQAmAAcJvBrWAQBTAQAuAAQKfzAABCYACQnXI6UCAPkCACYACQlLIqUCAPkCACEAAwk4FTEMAIAAAAUAAQlKGeIUAEgAAAAA.Katoumey:BAAALgAECggJDQABLgAFFAcJFgAmALwaAA==.Katøume:BAAALgAECgMJAwABLgAFFAcJFgAmALwaAA==.',
Ke='Keratin:BAABLgAECn8uAAInAAkJvSIhBACRAgAnAAkJvSIhBACRAgAAAA==.',
Kh='Khumi:BAABLgAECn8XAAIdAAgJYSCmEgCiAgAdAAgJYSCmEgCiAgABLgAFFAkJNwATAE8mAA==.',
Ki='Kil:BAAALgADCgUJBQAAAA==.Kinan:BAABLgAECn82AAMbAAkJHSYCAgB0AwAbAAkJHSYCAgB0AwAdAAcJOx6kFwBxAgAAAA==.Kita:BAAALgAECggJEgABLgAECgkJAgAVAAAAAA==.',
Kk='Kkaarrkk:BAAALgAECgUJCAAAAA==.',
Kr='Kreloenis:BAAALgAECgIJAgAAAA==.Krindon:BAABLgAECn8pAAIXAAgJIBLTHQCNAQAXAAgJIBLTHQCNAQAAAA==.',
Ku='Kureiji:BAAALgADCgEJAQAAAA==.',
Ky='Kythin:BAAALgAECgEJAgABLgAECgkJMQAIAMMbAA==.',
La='Lacutis:BAAALgAFFAEJAQAAAA==.Lanssolo:BAABLgAECn8VAAITAAgJjQZvJQB/AAATAAgJjQZvJQB/AAAAAA==.Larissa:BAAALgAFFAkJBAAAAA==.Laww:BAAALgADCgcJCgAAAA==.',
Le='Lecroix:BAAALgADCgUJBQAAAA==.Leonus:BAAALgAECgMJAwABLgAECgIJAgAVAAAAAA==.Lessana:BAAALgAECgQJDgAAAA==.Lethalforce:BAAALgADCgMJAwAAAA==.',
Li='Liandri:BAAALgADCgEJAgAAAA==.Lightchild:BAAALgADCggJCAAAAA==.Lightkilla:BAAALgAECgEJAQAAAA==.Lightprivlge:BAAALgAECgcJDQABLgAECgcJHAAWALoWAA==.Lillith:BAAALgAECgMJAwAAAA==.Livewire:BAABLgAECn8fAAMJAAUJLSJBBAB8AQAJAAQJLSJBBAB8AQAYAAQJSxD9FwB4AAAAAA==.',
Lo='Lokohmojo:BAAALgAECgMJBAAAAA==.Lomponic:BAEBLgAECn88AAIRAAkJ/x9XAgDjAQARAAkJ/x9XAgDjAQAAAA==.Lonelyone:BAAALgAECgQJBQAAAA==.Loomadin:BAAALgADCgYJCQAAAA==.Loranis:BAAALgAECgQJCgAAAA==.',
Lu='Lunethra:BAABLgAECn8rAAIbAAkJwhGAKwAGAgAbAAkJwhGAKwAGAgAAAA==.',
Ma='Mageaux:BAAALgAECgEJAgAAAA==.Magerag:BAACLgAFFH8JAAIIAAMJGBtgewDgAAAIAAMJGBtgewDgAAAuAAQKfy8AAwgACQlNIn8hAJgCAAgACQlNIn8hAJgCACUAAglAGkQVAHMAAAAA.Manamontana:BAACLgAFFH8cAAMWAAgJbw6oHwD1AQAWAAcJbw6oHwD1AQAgAAEJAACgUAAAAAAuAAQKfxoAAhYACAn4H4AoAJgCABYACAn4H4AoAJgCAAAA.Marumo:BAAALgAECgMJBgAAAA==.',
Mc='Mcribz:BAACLgAFFH8jAAIWAAgJEx6lCAArAgAWAAgJEx6lCAArAgAuAAQKfyIAAhYACAl8IzIZAOUCABYACAl8IzIZAOUCAAAA.',
Me='Meap:BAAALgAECgEJAQABLgAECgYJBgAVAAAAAA==.Meelonusk:BAAALgAECgQJCAAAAA==.Mess:BAAALgAECgYJEQAAAA==.Messah:BAAALgAECgQJCgAAAA==.Messic:BAAALgADCgEJAQAAAA==.',
Mi='Michaelcoyle:BAACLgAFFH8XAAIbAAQJWRbRFQBAAQAbAAQJWRbRFQBAAQAuAAQKfzwAAhsACAm9IeUFAOQBABsACAm9IeUFAOQBAAAA.Midnightcrow:BAAALgADCgkJDwAAAA==.Mikoto:BAAALgADCgcJBwAAAA==.Milo:BAACLgAFFH8RAAILAAQJFiHkDwCGAQALAAQJFiHkDwCGAQAuAAQKfzcAAwsACQlFI3gGAPYCAAsACQlFI3gGAPYCAAoACAluHBQEALQCAAAA.Minifru:BAAALgAECgQJBAAAAA==.Minlessu:BAAALgADCgEJAQABLgAECgEJAgAVAAAAAA==.Mishra:BAAALgAECgUJBQAAAA==.Mitra:BAABLgAECn9LAAIZAAkJZSSNAAA/AwAZAAkJZSSNAAA/AwAAAA==.',
Mo='Moesko:BAACLgAFFH8KAAIGAAMJHg8tSACXAAAGAAMJHg8tSACXAAAuAAQKfxUAAgYACQlwEtc+AJYBAAYACQlwEtc+AJYBAAAA.Mof:BAAALgADCgEJAQAAAA==.Mohawkk:BAAALgAECgQJBQAAAA==.Monktup:BAAALgAECgYJCwAAAA==.Monnehbaggs:BAABLgAECn81AAMcAAkJthyyDQCSAgAcAAgJCh2yDQCSAgASAAgJpR3/DQB7AgAAAA==.Mortalidad:BAAALgADCgQJBAAAAA==.',
Mu='Muin:BAAALgAECgEJAQAAAA==.Murdersamich:BAAALgAECgQJCwAAAA==.',
My='Mybigcrits:BAAALgAECgYJDAAAAA==.Myraghor:BAAALgADCgYJBgAAAA==.',
['Mà']='Màevë:BAAALgAECgEJAgAAAA==.',
Na='Nairdax:BAAALgADCgEJAQAAAA==.Nalmec:BAABLgAECn8hAAILAAYJPQhXXgDaAAALAAYJPQhXXgDaAAAAAA==.Nama:BAAALgADCgcJFAAAAA==.Naysayre:BAABLgAECn8wAAIPAAgJ4AdSiQAOAQAPAAgJ4AdSiQAOAQAAAA==.',
Ne='Nebody:BAAALgAECgYJEgAAAA==.Necriss:BAABLgAECn8sAAITAAkJUxD4ZACmAQATAAkJUxD4ZACmAQAAAA==.Nevereven:BAAALgAECgEJAQAAAA==.',
Ni='Nightkilla:BAAALgAECgEJAwAAAA==.Nike:BAAALgAECggJEAAAAA==.Nilowin:BAABLgAECn82AAIBAAkJCxFlFwDgAQABAAkJCxFlFwDgAQAAAA==.',
No='Nokaj:BAAALgAECgEJAgAAAA==.Noshards:BAAALgAECgcJDQAAAA==.Notericdh:BAAALgAECgYJEwAAAA==.',
Og='Oghom:BAAALgADCgcJEAAAAA==.',
Oh='Ohnoitzgumby:BAABLgAECn8cAAMWAAcJuhbvbACLAQAWAAcJrBbvbACLAQAnAAMJoBJPFABOAAAAAA==.',
Om='Omiko:BAAALgAECgIJAgAAAA==.',
Op='Opeep:BAAALgADCgcJGQAAAA==.',
Or='Orah:BAAALgADCgEJAQAAAA==.',
Os='Osos:BAAALgAECgYJEAAAAA==.',
Pa='Paladimdab:BAAALgAECgQJBQAAAA==.Papachance:BAABLgAECn8cAAIIAAgJhgiSnwA8AQAIAAgJhgiSnwA8AQAAAA==.Papafrank:BAAALgAECgYJDgAAAA==.Paradis:BAAALgADCgcJBwAAAA==.Pazuzu:BAAALgADCgYJBgAAAA==.',
Pe='Peepo:BAAALgAECgEJAQAAAA==.',
Ph='Phoenixwing:BAAALgADCgYJBgAAAA==.',
Pi='Pinga:BAACLgAFFH8GAAIcAAMJjgoQNQC3AAAcAAMJjgoQNQC3AAAuAAQKfykABBwACQk7ICkFADkDABwACQk7ICkFADkDABIAAgn6HOtfAFwAABEAAQmZDkSJADAAAAEuAAUUBAkLAB8ALRgA.Pinkberry:BAAALgAECgQJBAAAAA==.Pintcube:BAAALgADCgYJCAAAAA==.',
Pl='Pljeskavica:BAAALgAECgYJBwAAAA==.Plox:BAAALgAECgMJAwAAAA==.',
Po='Pookzilla:BAAALgAECgMJAwABLgAECgYJBwAVAAAAAA==.Port:BAABLgAECn8wAAIGAAkJ8R6NDAD6AgAGAAkJ8R6NDAD6AgAAAA==.Potroastjr:BAAALgAECgEJAgAAAA==.',
Pr='Preposition:BAAALgAECggJCQAAAA==.Primordus:BAAALgADCgUJBQAAAA==.Profiler:BAAALgAFFAIJAgAAAA==.Protocol:BAAALgAECgMJAwAAAA==.Prïestess:BAAALgAECgcJDAAAAA==.',
Ps='Pseriph:BAABLgAECn8ZAAIDAAcJ3BZrCwAKAgADAAcJ3BZrCwAKAgAAAA==.',
Py='Pyroclastic:BAAALgAECgkJAgAAAA==.',
Ra='Radamantis:BAAALgAECgQJBwAAAA==.Raenon:BAAALgAECgEJAQAAAA==.Raggnar:BAACLgAFFH8XAAIJAAQJDCJrFQBxAQAJAAQJDCJrFQBxAQAuAAQKfzEAAgkACQmVIakHAOICAAkACQmVIakHAOICAAAA.Ragingwaters:BAAALgADCgYJCAABLgAECgIJBgAVAAAAAA==.Ranvir:BAAALgAECgYJDgAAAA==.Raun:BAABLgAECn87AAMTAAkJBiPFCQAZAwATAAkJBiPFCQAZAwAOAAMJJBEvcgCzAAAAAA==.',
Re='Reactionhank:BAAALgAECgEJAgAAAA==.Regnarr:BAAALgADCgEJAQAAAA==.Rehgar:BAAALgAFFAEJAQAAAA==.Relaire:BAABLgAECn9KAAIbAAkJTxQHMwAQAgAbAAkJTxQHMwAQAgAAAA==.Remenissions:BAAALgAECgEJAQAAAA==.Resonate:BAAALgAFFAIJAwAAAA==.',
Ri='Rikane:BAAALgADCgcJDAABLgADCgcJEgAVAAAAAA==.Rikenji:BAAALgAECgEJAQABLgAFFAIJBwAIAF4OAA==.Riku:BAABLgAECn82AAImAAkJvSDSAgDzAgAmAAkJvSDSAgDzAgAAAA==.Ritehand:BAAALgAECgEJAgAAAA==.',
Ro='Rock:BAAALgAECgcJEgAAAA==.Rocks:BAAALgAECgEJAQAAAA==.Rockyrag:BAAALgAECgUJBQAAAA==.Roguey:BAABLgAECn8sAAMoAAkJuQ9KDABoAQAoAAcJlBFKDABoAQABAAcJ/wxIKQBNAQAAAA==.Roots:BAAALgAECgEJCAAAAA==.',
Ru='Rulethrefour:BAAALgAECgQJCAABLgAECgcJHAAWALoWAA==.',
Ry='Ryveri:BAABLgAECn8nAAILAAkJ1hnFHQAAAgALAAkJ1hnFHQAAAgAAAA==.',
Sa='Sablehide:BAABLgAECn81AAIHAAkJ4BnrEQBUAgAHAAkJ4BnrEQBUAgAAAA==.Sanaron:BAAALgADCgIJAgAAAA==.Sanaty:BAAALgAFFAIJBAAAAA==.Sarnak:BAAALgADCgMJAwAAAA==.Saryn:BAAALgAECgYJEwAAAA==.Satanz:BAAALgADCgIJAgAAAA==.Sathanus:BAABLgAECn8ZAAIPAAUJ6AwxFACuAAAPAAUJ6AwxFACuAAAAAA==.Sathir:BAAALgADCgMJAwAAAA==.',
Se='Searate:BAAALgADCgcJEgAAAA==.Seaside:BAACLgAFFH8PAAIWAAMJ/iX3HAAvAQAWAAMJ/iX3HAAvAQAuAAQKfxgAAxYABwk9JfZEAPMBABYABwk9JfZEAPMBACAAAgmEC+8/AE4AAAAA.Secrett:BAABLgAECn8hAAMBAAcJ4xXjBAAdAQABAAcJ4xXjBAAdAQAoAAEJew5gKQAwAAAAAA==.Sephyxia:BAABLgAECn8vAAIgAAkJdBqmDgAhAgAgAAkJdBqmDgAhAgAAAA==.Serryon:BAAALgADCgIJAgAAAA==.',
Sf='Sfora:BAAALgAECgUJBQAAAA==.',
Sh='Shadowreaper:BAAALgADCgYJBQAAAA==.Shadowwzz:BAAALgADCgEJAQAAAA==.Shiggs:BAAALgAECgcJCAAAAA==.Shocknezz:BAAALgAECgcJEAAAAA==.Shockwaves:BAAALgAECgEJAQAAAA==.Shoçknezz:BAAALgAECgMJBQAAAA==.',
Si='Silverwolf:BAABLgAECn9GAAIjAAkJ/SC1AgDrAgAjAAkJ/SC1AgDrAgAAAA==.Simplyunlock:BAACLgAFFH8gAAMCAAUJtwxXXgALAQACAAQJtwxXXgALAQAEAAEJAADaMQAAAAAuAAQKfycAAwIACQnzE4g0AAcCAAIACQnzE4g0AAcCAAMAAgnnBZVmAEMAAAAA.Simplyvoided:BAAALgAECgQJBgAAAA==.Sinfulcynic:BAAALgADCgQJBQAAAA==.Sinverguenza:BAAALgAECgMJBQAAAA==.Sizzlechop:BAABLgAECn8uAAMWAAkJ/g+piABTAQAWAAgJ7QqpiABTAQAgAAMJrBYfNQDDAAAAAA==.',
Sk='Skizzak:BAAALgADCgQJBAABLgAFFAgJIwAWABMeAA==.Skweeks:BAAALgAECgMJBAAAAA==.',
Sm='Smelvin:BAABLgAECn8cAAIJAAkJ8xlaHQD2AQAJAAkJ8xlaHQD2AQABLgAECgQJCAAVAAAAAA==.Smoko:BAAALgAECgIJAgABLgAECgUJBQAVAAAAAA==.',
Sn='Snailslolol:BAAALgAFFAMJBAAAAA==.Snakey:BAECLgAFFH8bAAMHAAUJGgmNPADVAAAHAAQJGgmNPADVAAAeAAIJ1wJTEAA5AAAuAAQKfywAAwcACAmLGD4aAPkBAAcACAmLGD4aAPkBAB4ABgl5BHkmAO8AAAAA.',
So='Solara:BAABLgAECn8hAAQRAAkJMRhAFwAPAgARAAkJMRhAFwAPAgASAAEJQAIShwApAAAcAAEJXgKYXgAkAAAAAA==.Soleill:BAAALgAECgcJBwAAAA==.Sondan:BAAALgADCgMJAwAAAA==.Songs:BAAALgAECgEJAQABLgAECgYJGAANAP8gAA==.',
Sp='Spellpowa:BAAALgAECgYJDgAAAA==.',
Sq='Squirtin:BAAALgAECgIJAgAAAA==.',
Ss='Ssminion:BAAALgAECgMJBgAAAA==.',
St='Stalath:BAAALgAECgUJCQAAAA==.Stiletto:BAAALgAECgEJAgAAAA==.Stormwing:BAABLgAECn8fAAMJAAgJiBmvJgC2AQAJAAgJiBmvJgC2AQAYAAEJMRY+zABAAAAAAA==.Strecagosa:BAAALgAECgYJDQAAAA==.',
Su='Sumarr:BAAALgAECgcJDAAAAA==.',
Sv='Svenn:BAAALgAECgYJCgAAAA==.',
Sw='Swiftstrike:BAAALgAECgMJAwAAAA==.',
Sy='Sybelissa:BAAALgAECgMJAwABLgAECgcJCgAVAAAAAA==.Synni:BAAALgADCgEJAQAAAA==.',
['Sÿ']='Sÿnÿster:BAAALgAECgQJBQABLgAFFAUJFwAbAJEcAA==.',
Ta='Taerion:BAAALgAECgEJAQAAAA==.Talron:BAAALgAECgYJDQAAAA==.Tastytay:BAAALgADCgMJAwAAAA==.Tatertots:BAABLgAECn8yAAMnAAkJFCCxAgDYAgAnAAkJFCCxAgDYAgAWAAMJ8hON7ACmAAAAAA==.',
Te='Tea:BAABLgAECn8xAAIbAAkJgCXgAwBTAwAbAAkJgCXgAwBTAwAAAA==.Teal:BAAALgAECgMJAwAAAA==.Templyn:BAACLgAFFH8FAAIWAAMJlAKweABMAAAWAAMJlAKweABMAAAuAAQKfzkAAxYACQkdFz0JAFgBACAACAnLFm0aAIoBABYACQm9ED0JAFgBAAAA.Templÿn:BAAALgAECgQJBAABLgAFFAMJBQAWAJQCAA==.Tenebrarum:BAABLgAECn8bAAIbAAgJGQ0xVwBjAQAbAAgJGQ0xVwBjAQAAAA==.Testorooni:BAABLgAECn8ZAAIbAAcJkBgpMwDjAQAbAAcJkBgpMwDjAQAAAA==.',
Th='Thakodi:BAAALgAECgQJBAAAAA==.Thannos:BAAALgADCgEJAQAAAA==.Tharvan:BAAALgADCgcJDAAAAA==.Thavok:BAAALgAECgEJAQAAAA==.Thedeadman:BAABLgAECn8kAAIWAAkJEyIrJAB0AgAWAAkJEyIrJAB0AgAAAA==.Thepriestg:BAAALgAECgEJAQAAAA==.Thiccksilver:BAAALgADCgcJBwABLgAFFAQJDwACAAUWAA==.Thompson:BAABLgAECn8VAAIWAAcJuxTvkwA/AQAWAAcJuxTvkwA/AQAAAA==.Thunderflaps:BAAALgAECgUJCQAAAA==.Thyrus:BAACLgAFFH8LAAIfAAQJLRgLFwAlAQAfAAQJLRgLFwAlAQAuAAQKfzUAAx8ACQk9Io0DAAwDAB8ACQk9Io0DAAwDAB4AAQmqAvtEACMAAAAA.',
Ti='Tirna:BAABLgAECn84AAIkAAkJng5yBACtAQAkAAkJng5yBACtAQAAAA==.',
To='Toebot:BAAALgAECgEJAgAAAA==.Toggle:BAAALgAECgEJAQAAAA==.Tomsellock:BAABLgAECn8WAAMEAAcJjhBuBwDcAQAEAAcJjhBuBwDcAQACAAEJugM+LAEmAAAAAA==.Tonari:BAAALgAECgEJAQABLgAECgYJEAAVAAAAAA==.Torvi:BAAALgADCgMJAwAAAA==.',
Tr='Transmørtuus:BAAALgAECgQJCQAAAA==.Treehug:BAAALgAECggJEwAAAA==.Triple:BAAALgAECgQJBwABLgAECgYJEAAVAAAAAA==.Trolleonne:BAAALgAECgIJAgAAAA==.',
Tu='Tullen:BAEBLgAECn81AAISAAkJjRGKIgCuAQASAAkJjRGKIgCuAQAAAA==.Turanos:BAABLgAECn8fAAIpAAUJfBBfBgDEAAApAAUJfBBfBgDEAAAAAA==.',
Tw='Tweyen:BAAALgAECgEJAQAAAA==.Twistedbael:BAAALgAECgUJBQAAAA==.',
Ty='Tyindaris:BAAALgAECgQJCgAAAA==.Tyloregeth:BAABLgAECn8sAAIRAAgJphSEKQCFAQARAAgJphSEKQCFAQAAAA==.',
['Tè']='Tèmplyn:BAAALgADCgEJAQABLgAFFAMJBQAWAJQCAA==.',
['Té']='Témplýn:BAAALgADCgEJAQABLgAFFAMJBQAWAJQCAA==.',
['Të']='Tëmplýn:BAAALgAECgQJBQABLgAFFAMJBQAWAJQCAA==.',
Ul='Ulfrunn:BAAALgADCgYJBgAAAA==.Ullr:BAAALgADCgcJCQAAAA==.Ultrachad:BAACLgAFFH8kAAIWAAgJYxnXDwBeAgAWAAgJYxnXDwBeAgAuAAQKfx4AAhYACAlNIwUUAAMDABYACAlNIwUUAAMDAAAA.',
Um='Umami:BAABLgAECn8gAAILAAYJ+RhzSgB7AQALAAYJ+RhzSgB7AQAAAA==.',
Un='Unggoy:BAACLgAFFH8zAAQdAAkJyyH8AgAkAgAdAAgJJCD8AgAkAgAbAAYJfxuvCADaAQAaAAQJyRQAEgA4AQAuAAQKfygAAx0ACQkhJrsBAKYDAB0ACQkhJrsBAKYDABsAAQnFJfX0AGsAAAAA.Unhollowed:BAAALgAECgIJBAAAAA==.Unholywaters:BAAALgAECgIJBgAAAA==.',
Ur='Urianna:BAAALgAECgYJCwAAAA==.',
Va='Vaelthirion:BAABLgAECn8nAAIIAAgJYxbETwDsAQAIAAgJYxbETwDsAQAAAA==.Vahidamus:BAAALgAECgkJEAAAAA==.Valkaryon:BAAALgAECgcJCgABLgAFFAIJAwAVAAAAAA==.Valmirax:BAAALgADCggJEgAAAA==.Valton:BAABLgAECn9wAAITAAgJaxgFBwC2AQATAAgJaxgFBwC2AQAAAA==.',
Ve='Vegetation:BAAALgAECgQJBwAAAA==.Velenestus:BAAALgAECgMJBgAAAA==.Verses:BAAALgADCgUJBQAAAA==.',
Vi='Vizsla:BAAALgAECgEJAQAAAA==.',
Wa='Wackaman:BAABLgAECn8uAAIMAAkJ3h9fCQBfAgAMAAkJ3h9fCQBfAgAAAA==.Waffleshirt:BAAALgAFFAEJAQAAAA==.Warpig:BAAALgAECgYJEQAAAA==.Wasps:BAAALgAECgYJEQAAAA==.',
We='Wegmaniac:BAAALgADCgYJCAAAAA==.Welastrexa:BAAALgADCgUJBQABLgAECgIJBgAVAAAAAA==.',
Wi='Wickedclöwn:BAAALgADCgMJAwAAAA==.Winchester:BAAALgADCgIJAgAAAA==.Windhorn:BAABLgAECn8pAAIdAAgJ0Qk1AgAUAQAdAAgJ0Qk1AgAUAQAAAA==.Winds:BAABLgAECn8YAAINAAYJ/yBoFwAqAgANAAYJ/yBoFwAqAgAAAA==.',
Wn='Wntrizcoming:BAAALgADCgMJBQAAAA==.',
Wo='Wolfen:BAAALgAECgYJBgAAAA==.Wolfquota:BAACLgAFFH8VAAIJAAUJYx8xCwBFAQAJAAUJYx8xCwBFAQAuAAQKfyQAAwkACAmCIkkJAP4CAAkACAmCIkkJAP4CACMABAntE08eAOkAAAAA.Wolftime:BAAALgADCgUJBQAAAA==.Wombaa:BAACLgAFFH8cAAMWAAUJoiXnFgB3AQAWAAUJoiXnFgB3AQAnAAIJPR77GgCxAAAuAAQKfxwAAhYACAleJGEKAEgDABYACAleJGEKAEgDAAAA.Woolybully:BAAALgAECgEJAQABLgAECgYJBwAVAAAAAA==.',
Wr='Wrathbolt:BAAALgAFFAMJBAABLgAFFAQJEQANAKgaAA==.Wrathmo:BAACLgAFFH8RAAMNAAQJqBrDEQAuAQANAAQJoRrDEQAuAQAUAAMJThBuDgDEAAAuAAQKfyUAAw0ACAljHG8UABcCAA0ABwlpHm8UABcCABQABwkdCqdAAPgAAAAA.Wrathp:BAABLgAFFH8QAAISAAQJuxXaFgAHAQASAAQJuxXaFgAHAQABLgAFFAQJEQANAKgaAA==.Wrolie:BAAALgADCgMJAwAAAA==.',
['Wê']='Wêêdyys:BAAALgADCgMJBAAAAA==.',
Xy='Xyr:BAEALgAECgEJAQABLgAECgkJQQARAPUYAA==.',
Ya='Yamiamigo:BAAALgAECgEJAwAAAA==.',
Yo='Yonah:BAAALgAECgEJAQAAAA==.Yougotsniped:BAAALgADCgEJAQAAAA==.',
Za='Zakos:BAAALgAECgcJCgAAAA==.Zandalia:BAAALgAECgMJAwAAAA==.Zark:BAEALgAECgEJAQABLgAECgkJGQAYAHsWAA==.Zarrallice:BAAALgAECgEJAQAAAA==.',
Ze='Zemphoths:BAAALgAECgcJCgAAAA==.Zephyra:BAAALgADCgEJAQABLgAECgUJBQAVAAAAAA==.',
Zo='Zoa:BAAALgADCgYJBgAAAA==.Zolton:BAAALgADCgMJAwAAAA==.Zornak:BAABLgAECn8hAAICAAYJsw6iDQDfAAACAAYJsw6iDQDfAAAAAA==.',
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
