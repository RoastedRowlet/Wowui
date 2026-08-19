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

local lookup = {'Rogue-Subtlety','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Druid-Balance','Druid-Restoration','Evoker-Augmentation','Mage-Frost','Shaman-Elemental','Hunter-BeastMastery','Warrior-Arms','Warrior-Fury','Warrior-Protection','Monk-Windwalker','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Shadow','Priest-Holy','Paladin-Retribution','Monk-Brewmaster','Unknown-Unknown','DeathKnight-Unholy','DemonHunter-Havoc','Shaman-Restoration','Rogue-Outlaw','Hunter-Survival','Priest-Discipline','Hunter-Marksmanship','Evoker-Devastation','Evoker-Preservation','DeathKnight-Blood','Druid-Guardian','Monk-Mistweaver','Shaman-Enhancement','Mage-Fire','Mage-Arcane','Druid-Feral','DeathKnight-Frost','Rogue-Assassination','Paladin-Protection',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=46,date='2026-08-18',data={Aa='Aamon:BAAALgAECgQJCgAAAA==.',
Ab='Abacus:BAABLgAECn8jAAIBAAkJjyLACwBoAgABAAkJjyLACwBoAgAAAA==.',
Ac='Acin:BAAALgADCgQJBAAAAA==.',
Ad='Adam:BAACLgAFFH84AAQCAAkJVSBkCQAwAgACAAcJbCFkCQAwAgADAAIJHyW/BgC/AAAEAAMJBhNcDQCiAAAuAAQKfy4ABAIACQk2JF4WAM4CAAIACQmcI14WAM4CAAQABQljJKcNAOsBAAMAAQkaI5QvAGAAAAAA.Adedruid:BAABLgAECn8gAAMFAAYJdR9cKwCnAQAFAAYJdR9cKwCnAQAGAAYJ3xoBSgB6AQAAAA==.Adevoker:BAAALgAECgQJBAAAAA==.Adragon:BAABLgAECn8rAAIHAAkJ5RpLDwByAgAHAAkJ5RpLDwByAgAAAA==.',
Ae='Aengyl:BAAALgAECgQJBAAAAA==.Aeonne:BAABLgAECn8WAAIIAAgJyxLYkQBUAQAIAAgJyxLYkQBUAQAAAA==.',
Ak='Akshul:BAABLgAECn8UAAIJAAYJ5Q1HRgAvAQAJAAYJ5Q1HRgAvAQAAAA==.Akurama:BAAALgAECgcJCgAAAA==.',
Al='Aldrea:BAAALgAECggJEgAAAA==.Alejandro:BAAALgAECgIJAgABLgAFFAkJDQAKALciAA==.Allsmiles:BAABLgAECn8VAAQLAAkJZh7tCAAhAgALAAgJhRrtCAAhAgAMAAUJChm2TQBwAQANAAQJkh4oKgDvAAAAAA==.Allura:BAABLgAECn8VAAIBAAgJSAraCADpAAABAAgJSAraCADpAAAAAA==.Alorian:BAAALgAECgIJAgAAAA==.Alttharius:BAAALgAECgMJAwABLgAECgkJHAAOAGMhAA==.Alyysha:BAABLgAECn8bAAIPAAcJlwkCRgBgAQAPAAcJlwkCRgBgAQAAAA==.',
Am='Amoon:BAABLgAECn81AAMQAAkJgBmXKAAoAgAQAAkJ0ReXKAAoAgARAAYJBRXYEgAjAQAAAA==.',
An='Angelrain:BAABLgAECn8sAAMSAAgJWByRDgCaAgASAAgJWByRDgCaAgATAAcJ8QcGPAAFAQAAAA==.Aniata:BAAALgAECgEJAQAAAA==.',
Ar='Archymedes:BAABLgAECn8sAAIMAAcJJxFLPgBMAQAMAAcJJxFLPgBMAQAAAA==.Arckady:BAABLgAECn8eAAIUAAgJqRulCQDZAQAUAAgJqRulCQDZAQAAAA==.Areko:BAAALgAECgIJBQAAAA==.Aresh:BAAALgAECgEJAgAAAA==.Array:BAAALgAECggJEgABLgAECgkJMAAGAPEeAA==.Artharius:BAABLgAECn8cAAMOAAkJYyGpFQALAgAOAAkJYyGpFQALAgAVAAEJohBHEgA/AAAAAA==.',
As='Asanad:BAAALgADCgUJBQABLgAECgYJDQAWAAAAAA==.',
Au='Auburnbeard:BAAALgADCgYJBgAAAA==.Aumed:BAAALgADCgEJAQAAAA==.Aurelionburn:BAAALgAECgEJAgAAAA==.',
Av='Averle:BAABLgAECn+CAAIEAAgJCA9gBAAzAQAEAAgJCA9gBAAzAQAAAA==.',
Ay='Ayahuascero:BAAALgAECgEJAQAAAA==.',
Az='Azrran:BAAALgADCgEJAQAAAA==.Aztharot:BAAALgAECgkJDgAAAA==.',
Ba='Badchoices:BAAALgAECgQJBAAAAA==.Badkittie:BAABLgAECn8VAAIIAAYJzgZ2MgCIAAAIAAYJzgZ2MgCIAAAAAA==.Balding:BAAALgAECgQJCAAAAA==.Baphico:BAAALgADCgUJCQAAAA==.',
Be='Bearhug:BAAALgAECgEJAQAAAA==.Beefsnake:BAEALgAFFAEJAQABLgAFFAYJHAAHAPgHAA==.Behemoth:BAAALgAECgQJBAAAAA==.Belinda:BAAALgAECgEJAQABLgAFFAkJMAAXAOMfAA==.Bettyßaraxus:BAAALgAECgMJAwABLgAECgkJMgAUAK8fAA==.Bettyßlight:BAABLgAECn8XAAIXAAgJxxrgBQAhAgAXAAgJxxrgBQAhAgABLgAECgkJMgAUAK8fAA==.Bewater:BAAALgADCgcJBwAAAA==.',
Bi='Bigcarol:BAAALgAECgEJAQAAAA==.Bigunsforu:BAABLgAECn8cAAIKAAkJcRPaCAD4AQAKAAkJcRPaCAD4AQAAAA==.',
Bl='Bladesmcgee:BAAALgAECggJCQABLgAECgQJCAAWAAAAAA==.Blasphem:BAAALgADCgQJBAAAAA==.',
Bo='Bobadelphia:BAAALgADCgYJBgABLgAECgYJEQAWAAAAAA==.Bofahdeez:BAABLgAECn8aAAMTAAgJfA6+PABHAQATAAcJWA6+PABHAQASAAcJLQwIPgAZAQAAAA==.Bogs:BAACLgAFFH8cAAIIAAYJLhkwIQBmAQAIAAYJLhkwIQBmAQAuAAQKfyMAAggACAnrIb4jAOQCAAgACAnrIb4jAOQCAAAA.Bolomorte:BAAALgAECgEJAQAAAA==.Bonedaddy:BAAALgAECgYJBgAAAA==.Boomstick:BAAALgAFFAEJAQABLgAFFAUJEgAQAB8OAA==.',
Br='Brewswayne:BAAALgADCgQJBAABLgAFFAIJAwAWAAAAAA==.Brolic:BAABLgAECn87AAMYAAkJuyEEBAAOAwAYAAkJuyEEBAAOAwAQAAEJJgnfKQEkAAAAAA==.',
['Bä']='Bämboo:BAAALgAFFAEJAgABLgAFFAUJDAAZACsVAA==.',
Ca='Cail:BAEBLgAECn8ZAAIZAAkJexYhIABPAgAZAAkJexYhIABPAgAAAA==.Calamìty:BAAALgADCgcJDgABLgAFFAQJDgAGAIUKAA==.Calisa:BAABLgAECn87AAIaAAkJ6h9nAQDnAgAaAAkJ6h9nAQDnAgAAAA==.Cardio:BAAALgAECgUJBgAAAA==.Carnifexx:BAABLgAFFH8GAAMZAAIJqxQfZAB/AAAZAAIJqxQfZAB/AAAJAAIJggmtSABtAAABLgAFFAIJBgAZAKsUAA==.Cassey:BAAALgAECgEJAQAAAA==.',
Ce='Celesteus:BAAALgADCgkJFAAAAA==.',
Ch='Charis:BAAALgAECgYJCwAAAA==.Chel:BAAALgAECgEJAQAAAA==.Chigutotems:BAAALgAECgYJCwABLgAECgkJGwAQAGwWAA==.Chimmoku:BAABLgAFFH8IAAIBAAQJ6RA/HAA6AQABAAQJ6RA/HAA6AQABLgAFFAkJQgABABQbAA==.Choi:BAAALgAECgUJDwAAAA==.Chooq:BAAALgADCgIJAgAAAA==.Chozen:BAAALgAECgUJEAAAAA==.Chumlee:BAAALgAECgYJDgAAAA==.',
Ci='Cienna:BAAALgAECgYJDgAAAA==.Cigz:BAAALgADCgEJAQAAAA==.Cinch:BAAALgAECgIJAgAAAA==.',
Cl='Cléavage:BAAALgAECgEJAgAAAA==.',
Co='Colinferral:BAAALgAECgYJCAAAAA==.Coulee:BAAALgAECgUJCwABLgAFFAMJCAAYAGkgAA==.Cowladin:BAAALgADCgUJBQAAAA==.',
Cr='Crakzkull:BAAALgAECgUJCwAAAA==.Croar:BAAALgAECgMJBAAAAA==.',
Cu='Cuernuda:BAAALgAECgEJAQAAAA==.',
['Cä']='Cäntstandya:BAACLgAFFH8RAAMbAAQJVRjeGwDyAAAbAAMJnxfeGwDyAAAKAAMJmRiVZQDaAAAuAAQKfyMAAwoACAkvG1cSAKUCAAoACAliGVcSAKUCABsABwkaHjsTAA0CAAAA.',
Da='Daiko:BAAALgAECgcJCwABLgAECgkJOQAcABUdAA==.Daks:BAAALgAFFAIJAwAAAA==.Dargo:BAAALgAECgYJEwAAAA==.Darklucrezia:BAACLgAFFH8YAAMKAAYJaRsbFACEAQAKAAYJaRsbFACEAQAdAAIJNgLRNQBIAAAuAAQKfy4AAwoACAn3H0QeAHACAAoACAltH0QeAHACAB0ACAkOEeQlAPoBAAAA.Darkpyro:BAAALgAECgIJAgAAAA==.Darkshuka:BAAALgAECgQJBAAAAA==.Dazzlefraz:BAAALgAECgQJBAAAAA==.',
De='Demonklunter:BAAALgADCgYJEAAAAA==.Denaida:BAAALgAECgIJAgAAAA==.Destructoid:BAAALgAECgEJAQAAAA==.',
Dg='Dgk:BAAALgAECgcJBwABLgAECgcJDAAWAAAAAA==.',
Dh='Dh:BAAALgAECgMJAwAAAA==.',
Di='Dicey:BAAALgADCgMJAwABLgAECgQJCAAWAAAAAA==.Dinkler:BAAALgAECgcJBwAAAA==.',
Do='Dochunter:BAAALgAECgUJBQAAAA==.',
Dr='Dracarius:BAABLgAECn8kAAQeAAgJfBhkAQCdAQAeAAgJfBhkAQCdAQAHAAMJIwvCdQB7AAAfAAIJgARwEQAcAAAAAA==.Drega:BAAALgAECgYJBwAAAA==.Droods:BAAALgAECgQJBQAAAA==.Drtypinkcake:BAABLgAECn8iAAIYAAkJ9wnbJABRAQAYAAkJ9wnbJABRAQAAAA==.Druskgar:BAABLgAECn8qAAMXAAkJMx8sMAA+AgAXAAkJMx8sMAA+AgAgAAcJ4A8sIwA5AQAAAA==.Dryad:BAABLgAECn8jAAIhAAgJMQzaCAAAAQAhAAgJMQzaCAAAAQAAAA==.',
Du='Duckster:BAAALgADCgYJBwAAAA==.Dunce:BAACLgAFFH8HAAIiAAIJdR+sPQCuAAAiAAIJdR+sPQCuAAAuAAQKfygAAiIACAnyIJsNAMMCACIACAnyIJsNAMMCAAAA.Durkk:BAABLgAECn87AAIgAAkJ9yFxBQDSAgAgAAkJ9yFxBQDSAgAAAA==.Durza:BAAALgAECgcJEAAAAA==.',
['Dä']='Dännydevito:BAAALgADCgQJBAAAAA==.',
Ea='Easyheal:BAAALgAECgUJCwABLgAECggJBQAWAAAAAA==.',
Ed='Eduard:BAAALgAECgYJCQAAAA==.',
Eg='Egon:BAAALgAECgQJBAABLgAFFAIJBwAIAF4OAA==.',
Ek='Eklipse:BAAALgAECgMJAwAAAA==.',
El='Elanthae:BAAALgAECgUJEgABLgAECgYJCQAWAAAAAA==.Elysia:BAAALgAECgEJAgAAAA==.',
Er='Erzulie:BAAALgAECgUJBAAAAA==.',
Es='Estara:BAABLgAECn81AAIhAAkJqwtbJgAhAQAhAAkJqwtbJgAhAQAAAA==.',
Et='Etali:BAABLgAECn8yAAIMAAkJQBwJEQBuAgAMAAkJQBwJEQBuAgAAAA==.',
Ex='Expired:BAAALgAECgEJAQAAAA==.',
Fa='Faite:BAAALgADCgUJBQAAAA==.Falorin:BAACLgAFFH8HAAIIAAIJXg5HogCKAAAIAAIJXg5HogCKAAAuAAQKfyIAAggACQm+F5NjALcBAAgACQm+F5NjALcBAAAA.Fanis:BAABLgAECn8mAAIdAAkJzRXLCQDYAQAdAAkJzRXLCQDYAQAAAA==.Fatherwhig:BAAALgAECgIJAwAAAA==.',
Fe='Fenrin:BAAALgAECgQJBwAAAA==.',
Fi='Fidis:BAAALgADCgkJCwAAAA==.Fistsofdeath:BAAALgADCggJCgAAAA==.Fistychub:BAAALgADCgEJAQAAAA==.',
Fl='Flashbang:BAAALgADCgEJAQAAAA==.Flashis:BAAALgAECggJEwAAAA==.Florago:BAABLgAECn8jAAIDAAcJrggCCQCkAAADAAcJrggCCQCkAAAAAA==.',
Fr='Frakir:BAABLgAECn87AAQZAAkJ5xlNGQCAAgAZAAkJ5xlNGQCAAgAjAAMJRwq0LQCLAAAJAAEJkAYjkwAjAAAAAA==.Fritzz:BAAALgAECgcJEgABLgAECgkJFAAFACcXAA==.Frog:BAAALgAECgIJBQAAAA==.',
Fu='Furrypaw:BAABLgAECn8uAAIiAAkJZiXLAQC8AwAiAAkJZiXLAQC8AwAAAA==.Fuzzyy:BAAALgAECgEJAQAAAA==.',
Fw='Fwapp:BAACLgAFFH8dAAIPAAkJZRlsCAA5AgAPAAkJZRlsCAA5AgAuAAQKfxcAAg8ACAlrIcgLAL8CAA8ACAlrIcgLAL8CAAAA.',
Ga='Galvanize:BAAALgAECgEJBQABLgAECgcJHAAXALoWAA==.Galynisse:BAABLgAECn8yAAMcAAgJAhjLFAA2AgAcAAgJAhjLFAA2AgATAAMJ7A4eZQCZAAAAAA==.Gannon:BAAALgAECgUJBQAAAA==.',
Ge='Gedorah:BAABLgAECn8fAAIkAAcJOBy1AwDYAQAkAAcJOBy1AwDYAQABLgAFFAQJFwAJAAwiAA==.Genny:BAAALgAECgIJAgAAAA==.',
Gh='Ghaspy:BAAALgAECgUJCgAAAA==.Ghoste:BAAALgADCgMJAwAAAA==.Ghrex:BAAALgAECgEJAQAAAA==.',
Gi='Gijaick:BAABLgAECn8wAAMCAAgJWBgHRwDFAQACAAgJWBgHRwDFAQAEAAEJHg4AdAAxAAAAAA==.',
Gl='Glaivethrow:BAABLgAECn8bAAIQAAkJbBZaPwDLAQAQAAkJbBZaPwDLAQAAAA==.Glizzo:BAABLgAFFH8GAAIIAAIJiRN9TgCYAAAIAAIJiRN9TgCYAAAAAA==.Gloam:BAAALgADCgUJBQAAAA==.Gloomrider:BAAALgADCgUJBwAAAA==.Glueballs:BAAALgAECgEJAQABLgAECgcJDAAWAAAAAA==.',
Go='Gochujjang:BAAALgAECgYJDQAAAA==.Golden:BAAALgAECgIJAgABLgAECggJJgAOAA4fAA==.Goldhawk:BAAALgAECggJDAAAAA==.Gosu:BAAALgAECgUJBQAAAA==.Gotchá:BAAALgAECgEJBAAAAA==.Gotwiped:BAABLgAECn8WAAIXAAgJfRqiOwASAgAXAAgJfRqiOwASAgAAAA==.',
Gr='Grexx:BAAALgAECgUJBQABLgAECgkJOQAcABUdAA==.Grimgor:BAAALgAECgcJAQAAAA==.',
Ha='Hahaheals:BAAALgAECgMJBAAAAA==.Hakhar:BAAALgADCgMJAwAAAA==.Hantaz:BAAALgAFFAEJAQAAAA==.Hanth:BAAALgADCgkJDAABLgAECgMJBAAWAAAAAA==.Haoleboy:BAAALgAECgYJCwAAAA==.Hatter:BAABLgAECn8pAAQQAAgJ4xXMQgC/AQAQAAgJ4xXMQgC/AQAYAAMJ+AsRWACGAAARAAEJNRMmKwA0AAAAAA==.',
He='Healsus:BAAALgAECgMJAwAAAA==.Heimlish:BAAALgAECgEJAQAAAA==.Hellbear:BAAALgADCgUJBQAAAA==.Hellraiser:BAABLgAECn8qAAMXAAkJORgeNwAiAgAXAAkJWhceNwAiAgAgAAcJlRNFIABRAQAAAA==.Hermione:BAAALgAECgYJDQAAAA==.Hexecution:BAAALgADCgIJAgAAAA==.',
Hi='Hiddendragon:BAAALgAECgEJAQAAAA==.Hidduka:BAAALgAECgEJAQABLgAECgkJFgAiAMYTAA==.',
Ho='Holydarkness:BAAALgAECgYJCwAAAA==.Holyhello:BAAALgAECgEJAQAAAA==.Holykilla:BAAALgAECgEJBQAAAA==.Holykiller:BAAALgAECgcJCgAAAA==.Hoofjob:BAAALgADCggJDgABLgAFFAcJFQAcALkfAA==.Hoplite:BAAALgAECgEJAQABLgAECggJEgAWAAAAAA==.Hotot:BAAALgADCgMJAwAAAA==.Howlly:BAABLgAECn9aAAIIAAkJDBu3BACCAgAIAAkJDBu3BACCAgAAAA==.',
Hu='Huffpuffle:BAAALgAECgUJCgAAAA==.',
['Hô']='Hôwl:BAABLgAECn8YAAIGAAcJwhBDSABuAQAGAAcJwhBDSABuAQAAAA==.',
Ic='Icdeathg:BAACLgAFFH8JAAIQAAMJ/QsRbACzAAAQAAMJ/QsRbACzAAAuAAQKfzEAAhAACAksH2AaAHYCABAACAksH2AaAHYCAAAA.',
Ik='Iktaar:BAAALgAECgYJEQAAAA==.',
Il='Illidami:BAAALgADCgkJCwAAAA==.Illidamngirl:BAAALgADCgYJBgABLgAECgkJLgANAN4fAA==.',
Im='Imperius:BAACLgAFFH8VAAIUAAUJHBb6SwAVAQAUAAUJHBb6SwAVAQAuAAQKfyQAAhQACQmMJB0OAB0DABQACQmMJB0OAB0DAAAA.',
In='Ines:BAACLgAFFH8KAAIXAAMJWSEkhwD7AAAXAAMJWSEkhwD7AAAuAAQKfzoAAhcACQlrJHELABIDABcACQlrJHELABIDAAAA.Insomiax:BAAALgAECggJDwAAAA==.Insta:BAABLgAECn8rAAIMAAcJzx3cIwA3AgAMAAcJzx3cIwA3AgAAAA==.Inter:BAABLgAECn8xAAIgAAkJwCI6BAALAwAgAAkJwCI6BAALAwAAAA==.',
Ir='Iridi:BAAALgADCgEJAQAAAA==.Iritall:BAAALgADCgcJCwABLgAECgEJAgAWAAAAAA==.',
It='Ithamburglar:BAAALgAECgQJBwAAAA==.',
Iz='Izureka:BAAALgADCgYJBgAAAA==.',
Ja='Jackidaytona:BAAALgAECgcJBwAAAA==.Jakaru:BAABLgAECn8bAAIiAAkJWRqYEgCJAgAiAAkJWRqYEgCJAgAAAA==.Jankadish:BAAALgAECgcJEwAAAA==.Jarre:BAACLgAFFH8GAAIGAAQJrggsDgAFAQAGAAQJrggsDgAFAQAuAAQKfygAAgYACAmzICIKAPMCAAYACAmzICIKAPMCAAAA.Jaspirian:BAAALgADCggJFAAAAA==.Jazzil:BAAALgADCgcJCgAAAA==.',
Jb='Jbaconcheese:BAAALgAECgEJAQAAAA==.',
Je='Jehm:BAAALgAECgIJAgABLgAECgMJAwAWAAAAAA==.Jehmkin:BAAALgAECgEJAQAAAA==.Jehmothy:BAAALgAECgUJBQAAAA==.Jerome:BAAALgAECgEJAQABLgAECgEJAgAWAAAAAA==.',
Jo='Jotabop:BAAALgAECgQJBgAAAA==.',
Ju='Judgequota:BAAALgAFFAMJAwABLgAFFAYJFgAJAEcgAA==.Juggsgotcha:BAABLgAFFH8HAAIXAAMJexKPSgDGAAAXAAMJexKPSgDGAAAAAA==.Juiceboxer:BAAALgAECgMJAwABLgAFFAIJAgAWAAAAAA==.Juicy:BAABLgAECn8kAAIbAAkJQRepDQBMAgAbAAkJQRepDQBMAgAAAA==.Justicehand:BAAALgADCgYJBgAAAA==.Juupiter:BAAALgAECgEJAQABLgAFFAIJBwAIAF4OAA==.',
Ka='Kabu:BAAALgAECgcJBwAAAA==.Kagor:BAAALgAECgYJCQAAAA==.Kalia:BAABLgAECn8xAAMIAAkJwxsVPgB/AgAIAAkJwxsVPgB/AgAlAAMJUg8vDgCXAAAAAA==.Kalipto:BAAALgADCgkJCgAAAA==.Kalitra:BAAALgADCgMJAwABLgAECgkJMQAIAMMbAA==.Kardaz:BAAALgAECgUJCQABLgAECggJcAAUAGwYAA==.Katatonik:BAAALgAECgUJCAABLgAECgYJCQAWAAAAAA==.Katharina:BAAALgAECgcJDAABLgAFFAEJAQAWAAAAAA==.Katoumae:BAACLgAFFH8XAAImAAcJ5hsIAgCPAQAmAAcJ5hsIAgCPAQAuAAQKfzAABCYACQnXI6UCAPkCACYACQlLIqUCAPkCACEAAwk4Fb8QAH8AAAUAAQlKGQAiAEQAAAAA.Katoumey:BAAALgAECggJDQABLgAFFAcJFwAmAOYbAA==.Katøume:BAAALgAECgMJAwABLgAFFAcJFwAmAOYbAA==.',
Ke='Keratin:BAABLgAECn8uAAInAAkJvSIhBACRAgAnAAkJvSIhBACRAgAAAA==.',
Kh='Khumi:BAABLgAECn8XAAIdAAgJYSCmEgCiAgAdAAgJYSCmEgCiAgABLgAFFAkJOQAUAE8mAA==.',
Ki='Kil:BAAALgAECgMJAwAAAA==.Kinan:BAABLgAECn82AAMKAAkJHSYCAgB0AwAKAAkJHSYCAgB0AwAdAAcJOx6kFwBxAgAAAA==.Kita:BAAALgAECggJEgABLgAECgkJAgAWAAAAAA==.',
Kk='Kkaarrkk:BAAALgAECgUJCAAAAA==.',
Kr='Kreloenis:BAAALgAECgIJAgAAAA==.Krindon:BAABLgAECn8pAAIYAAgJIBLTHQCNAQAYAAgJIBLTHQCNAQAAAA==.',
Ku='Kureiji:BAAALgADCgEJAQAAAA==.',
Ky='Kythin:BAAALgAECgEJAgABLgAECgkJMQAIAMMbAA==.',
La='Lacutis:BAAALgAFFAEJAQAAAA==.Lanssolo:BAABLgAECn8VAAIUAAgJjQZdzgD1AAAUAAgJjQZdzgD1AAAAAA==.Larissa:BAABLgAFFH8FAAIUAAMJaBvJKADnAAAUAAMJaBvJKADnAAAAAA==.Laww:BAAALgADCgcJCgAAAA==.',
Le='Lecroix:BAAALgADCgUJBQAAAA==.Leonus:BAAALgAECgMJBAABLgAECgIJAgAWAAAAAA==.Lessana:BAAALgAECgQJDgAAAA==.Lethalforce:BAAALgADCgMJAwAAAA==.',
Li='Liandri:BAAALgADCgEJAgAAAA==.Lightchild:BAAALgADCggJCAAAAA==.Lightkilla:BAAALgAECgEJAQAAAA==.Lightprivlge:BAAALgAECgcJDQABLgAECgcJHAAXALoWAA==.Lillith:BAAALgAECgMJAwAAAA==.Livewire:BAABLgAECn8kAAMJAAgJ4h45BwB0AQAJAAUJaCE5BwB0AQAZAAYJABYbEAAwAQAAAA==.',
Lo='Lokohmojo:BAAALgAECgMJBAAAAA==.Lomponic:BAEBLgAECn88AAISAAkJ/x8UBADYAQASAAkJ/x8UBADYAQAAAA==.Lonelyone:BAAALgAECgUJDQAAAA==.Loomadin:BAAALgADCgYJCQAAAA==.Loranis:BAAALgAECgUJCwABLgAECgYJCQAWAAAAAA==.',
Lu='Lunethra:BAABLgAECn8rAAIKAAkJwhGAKwAGAgAKAAkJwhGAKwAGAgAAAA==.',
Ma='Mageaux:BAAALgAECgEJAgAAAA==.Magerag:BAACLgAFFH8JAAIIAAMJGBtgewDgAAAIAAMJGBtgewDgAAAuAAQKfy8AAwgACQlNIn8hAJgCAAgACQlNIn8hAJgCACUAAglAGkQVAHMAAAAA.Malyc:BAAALgADCgcJBwAAAA==.Manamontana:BAACLgAFFH8dAAMXAAkJcA+oHwD1AQAXAAgJcA+oHwD1AQAgAAEJAACgUAAAAAAuAAQKfxoAAhcACAn4H4AoAJgCABcACAn4H4AoAJgCAAAA.Marshymallow:BAAALgAECgkJCgAAAA==.Marumo:BAAALgAECgMJBgAAAA==.',
Mc='Mcribz:BAACLgAFFH8wAAIXAAkJ4x9MBADZAgAXAAkJ4x9MBADZAgAuAAQKfyQAAhcACQm8JDIZAOUCABcACQm8JDIZAOUCAAAA.',
Me='Meap:BAAALgAECgIJAgABLgAECgYJBgAWAAAAAA==.Mechastrike:BAAALgAECgMJAwAAAA==.Meelonusk:BAAALgAECgQJCAAAAA==.Mess:BAABLgAECn8VAAIIAAcJEQuiHAD4AAAIAAcJEQuiHAD4AAAAAA==.Messah:BAAALgAECgQJCgAAAA==.Messic:BAAALgADCgEJAQAAAA==.',
Mi='Michaelcoyle:BAACLgAFFH8hAAIKAAQJeRiHGwBFAQAKAAQJeRiHGwBFAQAuAAQKfz4AAgoACQnWIS0EAJoCAAoACQnWIS0EAJoCAAAA.Midnightcrow:BAAALgADCgkJDwAAAA==.Mikoto:BAAALgAECgIJAgAAAA==.Milo:BAACLgAFFH8RAAIMAAQJFiHkDwCGAQAMAAQJFiHkDwCGAQAuAAQKfzcAAwwACQlFI3gGAPYCAAwACQlFI3gGAPYCAAsACAluHBQEALQCAAAA.Minifru:BAAALgAECgQJBAAAAA==.Minlessu:BAAALgADCgEJAQABLgAECgEJAgAWAAAAAA==.Mishra:BAAALgAECgUJBQAAAA==.Mitra:BAABLgAECn9YAAIaAAkJ4CSNAAA/AwAaAAkJ4CSNAAA/AwAAAA==.',
Mo='Moesko:BAACLgAFFH8LAAIGAAMJ2RAtSACXAAAGAAMJ2RAtSACXAAAuAAQKfxUAAgYACQlwEtc+AJYBAAYACQlwEtc+AJYBAAAA.Mof:BAAALgADCgEJAQAAAA==.Mohawkk:BAAALgAECgQJBQAAAA==.Monktup:BAAALgAECgYJCwAAAA==.Monnehbaggs:BAABLgAECn85AAMcAAkJFR2yDQCSAgAcAAgJNx6yDQCSAgATAAgJGR7/DQB7AgAAAA==.Mortalidad:BAAALgADCgQJBAAAAA==.',
Mu='Muin:BAAALgAECgEJAQAAAA==.Murdersamich:BAAALgAECgQJCwAAAA==.',
My='Mybigcrits:BAAALgAECgYJDAAAAA==.Myraghor:BAAALgADCgYJBgAAAA==.',
['Mà']='Màevë:BAAALgAECgEJAgAAAA==.',
Na='Nairdax:BAAALgADCgEJAQAAAA==.Nalmec:BAABLgAECn8hAAIMAAYJPQhXXgDaAAAMAAYJPQhXXgDaAAAAAA==.Nama:BAAALgADCgcJFAAAAA==.Naysayre:BAABLgAECn8wAAIQAAgJ4AdSiQAOAQAQAAgJ4AdSiQAOAQAAAA==.',
Ne='Nebody:BAABLgAECn8XAAIJAAYJZhyrCABKAQAJAAYJZhyrCABKAQAAAA==.Necriss:BAABLgAECn8sAAIUAAkJUxD4ZACmAQAUAAkJUxD4ZACmAQAAAA==.Nevereven:BAAALgAECgEJAQAAAA==.',
Ni='Nightkilla:BAAALgAECgEJAwAAAA==.Nike:BAAALgAECgkJEgAAAA==.Nilowin:BAABLgAECn82AAIBAAkJCxFlFwDgAQABAAkJCxFlFwDgAQAAAA==.',
No='Nokaj:BAAALgAECgEJAgAAAA==.Noshards:BAAALgAECgcJDQAAAA==.Notericdh:BAAALgAECgYJEwAAAA==.',
Oc='Occult:BAAALgAECgUJAwAAAA==.',
Og='Oghom:BAABLgAECn8WAAIUAAYJFghlLgCeAAAUAAYJFghlLgCeAAAAAA==.',
Oh='Ohnoitzgumby:BAABLgAECn8cAAMXAAcJuhbvbACLAQAXAAcJrBbvbACLAQAnAAMJoBJPFABOAAAAAA==.',
Om='Omiko:BAAALgAECgIJAgAAAA==.',
Op='Opeep:BAAALgADCgcJGQAAAA==.',
Or='Orah:BAAALgADCgEJAQAAAA==.',
Os='Osos:BAAALgAECgYJEAAAAA==.',
Pa='Paladimdab:BAAALgAECgQJBQAAAA==.Papachance:BAABLgAECn8cAAIIAAgJhgiSnwA8AQAIAAgJhgiSnwA8AQAAAA==.Papafrank:BAAALgAECgYJDgAAAA==.Paradis:BAAALgADCgcJBwAAAA==.Parlare:BAAALgAECgIJAgABLgAFFAQJCwAfAC0YAA==.Pazuzu:BAAALgADCgYJBgAAAA==.',
Pe='Peepo:BAAALgAECgEJAQAAAA==.',
Ph='Phoenixwing:BAAALgADCgYJBgAAAA==.Phun:BAAALgADCgYJBgAAAA==.',
Pi='Pinga:BAACLgAFFH8GAAIcAAMJjgoQNQC3AAAcAAMJjgoQNQC3AAAuAAQKfy0ABBwACQmYIikFADkDABwACQmYIikFADkDABMAAgn6HOtfAFwAABIAAQmZDkSJADAAAAEuAAUUBAkLAB8ALRgA.Pinkberry:BAAALgAECgQJBAAAAA==.Pintcube:BAAALgADCgYJCAAAAA==.',
Pl='Pljeskavica:BAAALgAECgYJBwAAAA==.Plox:BAAALgAECgMJAwAAAA==.',
Po='Pookzilla:BAAALgAECgQJBAABLgAECgYJBwAWAAAAAA==.Port:BAABLgAECn8wAAIGAAkJ8R6NDAD6AgAGAAkJ8R6NDAD6AgAAAA==.Potroastjr:BAAALgAECgEJAgAAAA==.',
Pr='Preposition:BAAALgAECggJCQAAAA==.Primordus:BAAALgADCgUJBQAAAA==.Profiler:BAAALgAFFAIJAgAAAA==.Protocol:BAAALgAECgMJAwAAAA==.Prïestess:BAAALgAECgcJDAAAAA==.',
Ps='Pseriph:BAABLgAECn8ZAAIEAAcJ3BZrCwAKAgAEAAcJ3BZrCwAKAgAAAA==.',
Py='Pyroclastic:BAAALgAECgkJAgAAAA==.',
Ra='Radamantis:BAAALgAECgQJBwAAAA==.Raenon:BAAALgAECgEJAQAAAA==.Raggnar:BAACLgAFFH8XAAIJAAQJDCJrFQBxAQAJAAQJDCJrFQBxAQAuAAQKfzEAAgkACQmVIakHAOICAAkACQmVIakHAOICAAAA.Ragingwaters:BAAALgADCgYJCAABLgAECgIJBgAWAAAAAA==.Ranvir:BAAALgAECgYJDgAAAA==.Raun:BAABLgAECn87AAMUAAkJBiPFCQAZAwAUAAkJBiPFCQAZAwAPAAMJJBEvcgCzAAAAAA==.Razzidan:BAAALgADCgkJCQAAAA==.',
Re='Reactionhank:BAAALgAECgYJAgAAAA==.Regnarr:BAAALgADCgEJAQAAAA==.Rehgar:BAAALgAFFAEJAQAAAA==.Relaire:BAABLgAECn9KAAIKAAkJTxQHMwAQAgAKAAkJTxQHMwAQAgAAAA==.Remenissions:BAAALgAECgEJAQAAAA==.Resonate:BAAALgAFFAIJAwAAAA==.',
Ri='Rikane:BAAALgADCgcJDAABLgADCgcJEgAWAAAAAA==.Rikenji:BAAALgAECgEJAQABLgAFFAIJBwAIAF4OAA==.Riku:BAABLgAECn82AAImAAkJvSDSAgDzAgAmAAkJvSDSAgDzAgAAAA==.Ritehand:BAAALgAECgEJAgAAAA==.',
Ro='Rock:BAAALgAECgcJEgAAAA==.Rocks:BAAALgAECgEJAQAAAA==.Rockyrag:BAAALgAECgUJBQAAAA==.Roguey:BAABLgAECn8sAAMoAAkJuQ9KDABoAQAoAAcJlBFKDABoAQABAAcJ/wxIKQBNAQAAAA==.Roots:BAAALgAECgEJCAAAAA==.',
Ru='Rulethrefour:BAAALgAECgQJCAABLgAECgcJHAAXALoWAA==.',
Ry='Ryveri:BAABLgAECn8nAAIMAAkJ1hnFHQAAAgAMAAkJ1hnFHQAAAgAAAA==.',
Sa='Sablehide:BAABLgAECn81AAIHAAkJ4BnrEQBUAgAHAAkJ4BnrEQBUAgAAAA==.Sanaron:BAAALgADCgIJAgAAAA==.Sanaty:BAAALgAFFAIJBAAAAA==.Sarnak:BAAALgADCgMJAwAAAA==.Saryn:BAAALgAECgYJEwAAAA==.Satanz:BAAALgADCgIJAgAAAA==.Sathanus:BAABLgAECn8dAAIQAAcJ+xABEwDwAAAQAAcJ+xABEwDwAAAAAA==.Sathir:BAAALgADCgMJAwAAAA==.Sazibara:BAAALgADCgcJBwAAAA==.',
Se='Searate:BAAALgADCgcJEgAAAA==.Seaside:BAACLgAFFH8PAAIXAAMJ/iX3HAAvAQAXAAMJ/iX3HAAvAQAuAAQKfxgAAxcABwk9JfZEAPMBABcABwk9JfZEAPMBACAAAgmEC+8/AE4AAAAA.Secrett:BAABLgAECn8hAAMBAAcJ4xVzBwANAQABAAcJ4xVzBwANAQAoAAEJew5gKQAwAAAAAA==.Sephyxia:BAABLgAECn8vAAIgAAkJdBqmDgAhAgAgAAkJdBqmDgAhAgAAAA==.Serryon:BAAALgADCgIJAgAAAA==.',
Sf='Sfora:BAAALgAECgYJBgAAAA==.',
Sh='Shadowreaper:BAAALgADCgYJBQAAAA==.Shadowwzz:BAAALgADCgEJAQAAAA==.Shelby:BAAALgAECgQJBAAAAA==.Shiggs:BAAALgAECgcJDgAAAA==.Shocknezz:BAAALgAECgcJEAAAAA==.Shockwaves:BAAALgAECgEJAQAAAA==.Shovel:BAAALgAECgEJAQAAAA==.Shoçknezz:BAAALgAECgMJBQAAAA==.',
Si='Silverwolf:BAABLgAECn9NAAIjAAkJ3iG1AgDrAgAjAAkJ3iG1AgDrAgAAAA==.Simplyunlock:BAACLgAFFH8gAAMCAAUJtwxXXgALAQACAAQJtwxXXgALAQADAAEJAADaMQAAAAAuAAQKfycAAwIACQnzE4g0AAcCAAIACQnzE4g0AAcCAAQAAgnnBZVmAEMAAAAA.Simplyvoided:BAAALgAECgQJBgAAAA==.Sinfulcynic:BAAALgADCgQJBQAAAA==.Sinverguenza:BAAALgAECgMJBQAAAA==.Sizzlechop:BAABLgAECn8uAAMXAAkJ/g+piABTAQAXAAgJ7QqpiABTAQAgAAMJrBYfNQDDAAAAAA==.',
Sk='Skizzak:BAAALgAFFAEJAQABLgAFFAkJMAAXAOMfAA==.Skweeks:BAAALgAECgMJBAAAAA==.',
Sm='Smelvin:BAABLgAECn8cAAIJAAkJ8xlaHQD2AQAJAAkJ8xlaHQD2AQABLgAECgQJCAAWAAAAAA==.Smoko:BAAALgAECgIJAgABLgAECgUJBQAWAAAAAA==.',
Sn='Snailslolol:BAAALgAFFAMJBAAAAA==.Snakey:BAECLgAFFH8cAAMHAAYJ+AeNPADVAAAHAAUJ+AeNPADVAAAeAAIJ1wJTEAA5AAAuAAQKfywAAwcACAmLGD4aAPkBAAcACAmLGD4aAPkBAB4ABgl5BHkmAO8AAAAA.',
So='Solara:BAABLgAECn8hAAQSAAkJMRhAFwAPAgASAAkJMRhAFwAPAgATAAEJQAIShwApAAAcAAEJXgKYXgAkAAAAAA==.Soleill:BAAALgAECgcJBwAAAA==.Sondan:BAAALgADCgMJAwAAAA==.Songs:BAAALgAECgcJBQABLgAECggJJgAOAA4fAA==.',
Sp='Spellpowa:BAAALgAECgYJDgAAAA==.',
Sq='Squirtin:BAAALgAECgIJAgAAAA==.',
Ss='Ssminion:BAAALgAECgMJBgAAAA==.',
St='Stalath:BAAALgAECgUJCQAAAA==.Stiletto:BAAALgAECgEJAgAAAA==.Stormwing:BAABLgAECn8fAAMJAAgJiBmvJgC2AQAJAAgJiBmvJgC2AQAZAAEJMRY+zABAAAAAAA==.Strecagosa:BAAALgAECgYJDQAAAA==.',
Su='Sumarr:BAAALgAECgcJDAAAAA==.',
Sv='Svenn:BAAALgAECgYJCgAAAA==.',
Sw='Swiftstrike:BAAALgAECgMJAwAAAA==.',
Sy='Sybelissa:BAAALgAECgMJAwABLgAECgcJCgAWAAAAAA==.Synni:BAAALgADCgEJAQAAAA==.',
['Sÿ']='Sÿnÿster:BAAALgAECgQJBQABLgAFFAYJGAAKAGkbAA==.',
Ta='Taerion:BAAALgAECgUJBgABLgAECgYJCQAWAAAAAA==.Talron:BAAALgAECgYJDQAAAA==.Tastytay:BAAALgADCgMJAwAAAA==.Tatertots:BAABLgAECn8yAAMnAAkJFCCxAgDYAgAnAAkJFCCxAgDYAgAXAAMJ8hON7ACmAAAAAA==.',
Te='Tea:BAABLgAECn8xAAIKAAkJgCXgAwBTAwAKAAkJgCXgAwBTAwAAAA==.Teal:BAAALgAECgMJAwAAAA==.Templyn:BAACLgAFFH8KAAMgAAMJHQyTGQCPAAAgAAMJHQyTGQCPAAAXAAMJSgWIeABpAAAuAAQKf0IAAyAACQlGGr0DANYBACAACAkDG70DANYBABcACQlcElEMAHUBAAAA.Templÿn:BAAALgAECgQJBAABLgAFFAMJCgAgAB0MAA==.Tenebrarum:BAABLgAECn8bAAIKAAgJGQ0xVwBjAQAKAAgJGQ0xVwBjAQAAAA==.Testorooni:BAABLgAECn8ZAAIKAAcJkBgpMwDjAQAKAAcJkBgpMwDjAQAAAA==.',
Th='Thakodi:BAAALgAECgQJBAAAAA==.Thannos:BAAALgADCgEJAQAAAA==.Tharvan:BAAALgADCgcJDAAAAA==.Thavok:BAAALgAECgEJAQAAAA==.Thedeadman:BAABLgAECn8kAAIXAAkJEyIrJAB0AgAXAAkJEyIrJAB0AgAAAA==.Thepriestg:BAAALgAECgEJAQAAAA==.Thiccksilver:BAAALgADCgcJBwABLgAFFAQJDwACAAUWAA==.Thompson:BAABLgAECn8VAAIXAAcJuxTvkwA/AQAXAAcJuxTvkwA/AQAAAA==.Thunderflaps:BAAALgAECgUJCQAAAA==.Thyrus:BAACLgAFFH8LAAIfAAQJLRgLFwAlAQAfAAQJLRgLFwAlAQAuAAQKfzUAAx8ACQk9Io0DAAwDAB8ACQk9Io0DAAwDAB4AAQmqAvtEACMAAAAA.',
Ti='Tirna:BAABLgAECn84AAIkAAkJng5yBACtAQAkAAkJng5yBACtAQAAAA==.',
To='Toebot:BAAALgAECgEJAgAAAA==.Toggle:BAAALgAECgEJAQAAAA==.Tomsellock:BAABLgAECn8WAAMDAAcJjhBuBwDcAQADAAcJjhBuBwDcAQACAAEJugM+LAEmAAAAAA==.Tonari:BAAALgAECgEJAQABLgAECgYJEAAWAAAAAA==.Torvi:BAAALgADCgMJAwAAAA==.',
Tr='Transmørtuus:BAAALgAECgQJCQAAAA==.Treehug:BAAALgAECggJEwAAAA==.Triple:BAAALgAECgQJBwABLgAECgYJEAAWAAAAAA==.Trolleonne:BAAALgAECgIJAgAAAA==.',
Tu='Tullen:BAEBLgAECn81AAITAAkJjRGKIgCuAQATAAkJjRGKIgCuAQAAAA==.Turanos:BAABLgAECn8kAAIpAAgJsQ7kBgAOAQApAAgJsQ7kBgAOAQAAAA==.',
Tw='Tweyen:BAAALgAECgEJAQAAAA==.Twistedbael:BAAALgAECgUJBQAAAA==.',
Ty='Tyindaris:BAAALgAECgQJCgAAAA==.Tyleros:BAAALgADCgMJAwAAAA==.Tyloregeth:BAABLgAECn8sAAISAAgJphSEKQCFAQASAAgJphSEKQCFAQAAAA==.',
['Tè']='Tèmplyn:BAAALgADCgEJAQABLgAFFAMJCgAgAB0MAA==.',
['Té']='Témplýn:BAAALgAECgEJAQABLgAFFAMJCgAgAB0MAA==.Téz:BAABLgAECn8qAAQTAAcJ0hwZAwAdAgATAAYJ0h8ZAwAdAgASAAYJvhefCgAZAQAcAAEJihgJIQBIAAAAAA==.',
['Të']='Tëmplýn:BAAALgAECgQJBgABLgAFFAMJCgAgAB0MAA==.',
Ul='Ulfrunn:BAAALgADCgYJBgAAAA==.Ullr:BAABLgAECn8XAAIdAAcJ2gw2BAD4AAAdAAcJ2gw2BAD4AAAAAA==.Ultrachad:BAACLgAFFH8rAAIXAAkJ/h3XDwBeAgAXAAkJ/h3XDwBeAgAuAAQKfx4AAhcACAlNIwUUAAMDABcACAlNIwUUAAMDAAAA.',
Um='Umami:BAABLgAECn8gAAIMAAYJ+RhzSgB7AQAMAAYJ+RhzSgB7AQAAAA==.',
Un='Unggoy:BAACLgAFFH9FAAQKAAkJiiLoBgBQAgAKAAYJGiLoBgBQAgAdAAgJTCD8AgAkAgAbAAUJNxEAEgA4AQAuAAQKfygAAx0ACQkhJrsBAKYDAB0ACQkhJrsBAKYDAAoAAQnFJfX0AGsAAAAA.Unhollowed:BAAALgAECgIJBAAAAA==.Unholywaters:BAAALgAECgIJBgAAAA==.',
Ur='Urianna:BAAALgAECgYJCwAAAA==.',
Va='Vaelthirion:BAABLgAECn8nAAIIAAgJYxbETwDsAQAIAAgJYxbETwDsAQAAAA==.Vahidamus:BAABLgAECn8bAAMZAAkJWg79CwBzAQAZAAkJWg79CwBzAQAJAAEJygGUwwAZAAAAAA==.Valkaryon:BAAALgAECgcJCgABLgAFFAIJAwAWAAAAAA==.Valmirax:BAAALgADCggJEgAAAA==.Valton:BAABLgAECn9wAAIUAAgJbBjeCwCrAQAUAAgJbBjeCwCrAQAAAA==.',
Ve='Vegetation:BAAALgAECgQJCAAAAA==.Velenestus:BAAALgAECgMJBgAAAA==.Verses:BAAALgADCgUJBQAAAA==.',
Vi='Vizsla:BAAALgAECgEJAQAAAA==.',
Wa='Wackalock:BAAALgADCgYJBgABLgAECgkJLgANAN4fAA==.Wackaman:BAABLgAECn8uAAINAAkJ3h9fCQBfAgANAAkJ3h9fCQBfAgAAAA==.Waffleshirt:BAAALgAFFAEJAQAAAA==.Warpig:BAAALgAECgYJEQAAAA==.Wasps:BAAALgAECgYJEQAAAA==.',
We='Wegmaniac:BAAALgADCgYJCAAAAA==.Welastrexa:BAAALgADCgUJBQABLgAECgIJBgAWAAAAAA==.Westros:BAAALgAECgkJCQABLgAFFAIJAwAWAAAAAA==.',
Wi='Wickedclöwn:BAAALgADCgMJAwAAAA==.Winchester:BAAALgADCgIJAgAAAA==.Windhorn:BAABLgAECn8xAAIdAAgJXg3VAgBCAQAdAAgJXg3VAgBCAQAAAA==.Winds:BAABLgAECn8mAAIOAAgJDh/0AQBCAgAOAAgJDh/0AQBCAgAAAA==.',
Wn='Wntrizcoming:BAAALgADCgMJBQAAAA==.',
Wo='Wolfen:BAAALgAECgYJBgAAAA==.Wolfquota:BAACLgAFFH8WAAIJAAYJRyBqCwCOAQAJAAYJRyBqCwCOAQAuAAQKfyQAAwkACAmCIkkJAP4CAAkACAmCIkkJAP4CACMABAntE08eAOkAAAAA.Wolftime:BAAALgADCgUJBQAAAA==.Wombaa:BAACLgAFFH8dAAMXAAYJiSW9FADIAQAXAAYJiSW9FADIAQAnAAIJPR77GgCxAAAuAAQKfxwAAhcACAleJGEKAEgDABcACAleJGEKAEgDAAAA.Woolybully:BAAALgAECgEJAQABLgAECgYJBwAWAAAAAA==.',
Wr='Wrathbolt:BAAALgAFFAMJBAABLgAFFAUJHwAOAKgaAA==.Wrathmo:BAACLgAFFH8fAAMOAAUJqBrDEQAuAQAOAAQJoRrDEQAuAQAVAAQJThC8EQDBAAAuAAQKfygAAw4ACQlPG28UABcCAA4ABwlpHm8UABcCABUACQltC6YIAKoAAAAA.Wrathp:BAABLgAFFH8QAAITAAQJuxXaFgAHAQATAAQJuxXaFgAHAQABLgAFFAUJHwAOAKgaAA==.Wrolie:BAAALgADCgMJAwAAAA==.',
['Wê']='Wêêdyys:BAAALgADCgMJBAAAAA==.',
Xy='Xyr:BAEALgAECgEJAQABLgAECgkJQQASAPUYAA==.',
Ya='Yamiamigo:BAAALgAECgEJAwAAAA==.',
Yo='Yonah:BAAALgAECgEJAQAAAA==.Yougotsniped:BAAALgADCgEJAQAAAA==.',
Za='Zakos:BAAALgAECgcJCgAAAA==.Zandalia:BAAALgAECgMJAwAAAA==.Zark:BAEALgAECgEJAQABLgAECgkJGQAZAHsWAA==.Zarrallice:BAAALgAECgEJAQAAAA==.',
Ze='Zemphoths:BAAALgAECgcJCgAAAA==.Zephyra:BAAALgADCgEJAQABLgAECgYJBgAWAAAAAA==.',
Zo='Zoa:BAAALgADCgYJBgAAAA==.Zolton:BAAALgADCgMJAwAAAA==.Zornak:BAABLgAECn8hAAICAAYJsw43FADUAAACAAYJsw43FADUAAAAAA==.',
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
