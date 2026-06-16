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

local lookup = {'Rogue-Subtlety','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Balance','Druid-Restoration','Evoker-Augmentation','Mage-Frost','Shaman-Elemental','Warrior-Arms','Warrior-Fury','Warrior-Protection','Monk-Windwalker','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Vengeance','Unknown-Unknown','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','Paladin-Retribution','DemonHunter-Havoc','Shaman-Restoration','Rogue-Outlaw','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Devastation','Evoker-Preservation','DeathKnight-Blood','Druid-Guardian','Monk-Mistweaver','Shaman-Enhancement','Priest-Discipline','Mage-Fire','Mage-Arcane','Druid-Feral','DeathKnight-Frost','Rogue-Assassination','Paladin-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aamon:BAAALgAECgQJCgAAAA==.',
Ab='Abacus:BAABLgAECn8jAAIBAAkJjyKBCwBpAgABAAkJjyKBCwBpAgAAAA==.',
Ac='Acin:BAAALgADCgQJBAAAAA==.',
Ad='Adam:BAACLgAFFH8ZAAQCAAcJWxuMPABTAQACAAUJLhyMPABTAQADAAMJlBFcDQCiAAAEAAEJECbeEgBvAAAuAAQKfy4ABAIACQk2JF4WAM4CAAIACQmcI14WAM4CAAMABQljJKcNAOsBAAQAAQkaI1cuAGAAAAAA.Adedruid:BAABLgAECn8gAAMFAAYJdR9cKwCnAQAFAAYJdR9cKwCnAQAGAAYJ3xoBSgB6AQAAAA==.Adevoker:BAAALgAECgQJBAAAAA==.Adragon:BAABLgAECn8rAAIHAAkJ5RobDwByAgAHAAkJ5RobDwByAgAAAA==.',
Ae='Aengyl:BAAALgAECgQJBAAAAA==.Aeonne:BAABLgAECn8WAAIIAAgJyxL5jwBUAQAIAAgJyxL5jwBUAQAAAA==.',
Ak='Akshul:BAABLgAECn8UAAIJAAYJ5Q1HRgAvAQAJAAYJ5Q1HRgAvAQAAAA==.Akurama:BAAALgAECgcJCgAAAA==.',
Al='Aldrea:BAAALgAECggJEQAAAA==.Allsmiles:BAABLgAECn8VAAQKAAkJZh7tCAAhAgAKAAgJhRrtCAAhAgALAAUJChm2TQBwAQAMAAQJkh4oKgDvAAAAAA==.Allura:BAAALgAECgUJDQAAAA==.Alorian:BAAALgAECgIJAgAAAA==.Alttharius:BAAALgAECgMJAwABLgAECgkJGwANAGMhAA==.Alyysha:BAABLgAECn8bAAIOAAcJlwkCRgBgAQAOAAcJlwkCRgBgAQAAAA==.',
Am='Amoon:BAABLgAECn81AAMPAAkJgBn/JwAoAgAPAAkJ0Rf/JwAoAgAQAAYJBRWREgAjAQAAAA==.',
An='Andoriel:BAAALgADCgcJBwABLgAFFAIJAwARAAAAAA==.Angelrain:BAABLgAECn8sAAMSAAgJWByRDgCaAgASAAgJWByRDgCaAgATAAcJ8QcfOwAFAQAAAA==.Aniata:BAAALgAECgEJAQAAAA==.',
Ar='Archymedes:BAABLgAECn8sAAILAAcJJxEvPQBQAQALAAcJJxEvPQBQAQAAAA==.Arckady:BAAALgAECgQJDwAAAA==.Areko:BAAALgAECgIJBQAAAA==.Aresh:BAAALgAECgEJAgAAAA==.Array:BAAALgAECgYJCwABLgAECgkJMAAGAPEeAA==.Artharius:BAABLgAECn8bAAINAAkJYyEnFQAOAgANAAkJYyEnFQAOAgAAAA==.',
As='Asanad:BAAALgADCgUJBQABLgAECgUJCAARAAAAAA==.',
Au='Auburnbeard:BAAALgADCgYJBgAAAA==.Aumed:BAAALgADCgEJAQAAAA==.Aurelionburn:BAAALgAECgEJAQAAAA==.',
Av='Averle:BAABLgAECn9lAAIDAAcJpwtPFQD8AAADAAcJpwtPFQD8AAAAAA==.',
Az='Azrran:BAAALgADCgEJAQAAAA==.Aztharot:BAAALgAECgIJAgAAAA==.',
Ba='Badchoices:BAAALgAECgQJBAAAAA==.Badkittie:BAAALgAECgQJBwAAAA==.Balding:BAAALgAECgQJCAAAAA==.Baphico:BAAALgADCgUJCQAAAA==.',
Be='Bearhug:BAAALgAECgEJAQAAAA==.Behemoth:BAAALgAECgQJBAAAAA==.Belinda:BAAALgAECgEJAQABLgAFFAYJGwAUAMgjAA==.Bettyßaraxus:BAAALgAECgMJAwABLgAECgkJMgAVAK8fAA==.Bewater:BAAALgADCgcJBwAAAA==.',
Bi='Bigcarol:BAAALgAECgEJAQAAAA==.Bigunsforu:BAAALgAECgUJCAAAAA==.',
Bl='Bladesmcgee:BAAALgAECggJCQABLgAECgQJCAARAAAAAA==.Blasphem:BAAALgADCgQJBAAAAA==.',
Bo='Bobadelphia:BAAALgADCgYJBgABLgAECgYJEQARAAAAAA==.Bofahdeez:BAABLgAECn8aAAMTAAgJfA6+PABHAQATAAcJWA6+PABHAQASAAcJLQy3PAAcAQAAAA==.Bogs:BAACLgAFFH8XAAIIAAUJmx0sSQBVAQAIAAUJmx0sSQBVAQAuAAQKfyMAAggACAnrIb4jAOQCAAgACAnrIb4jAOQCAAAA.Bonedaddy:BAAALgAECgYJBgAAAA==.Boomstick:BAAALgAECgYJCAABLgAFFAUJEgAPAB8OAA==.',
Br='Brewswayne:BAAALgADCgQJBAABLgAFFAIJAwARAAAAAA==.Brolic:BAABLgAECn85AAMWAAkJfCEQBAAJAwAWAAkJfCEQBAAJAwAPAAEJJgnHJAEkAAAAAA==.',
['Bä']='Bämboo:BAAALgAFFAEJAgABLgAFFAQJCwAXAOoQAA==.',
Ca='Cail:BAEBLgAECn8ZAAIXAAkJexZ/HwBPAgAXAAkJexZ/HwBPAgAAAA==.Calamìty:BAAALgADCgcJDgABLgAFFAMJCgAGAJYMAA==.Calisa:BAABLgAECn87AAIYAAkJ6h9eAQDnAgAYAAkJ6h9eAQDnAgAAAA==.Cardio:BAAALgAECgUJBgAAAA==.Carnifexx:BAAALgAFFAIJBAABLgAFFAgJIAAPAGEVAA==.Cassey:BAAALgAECgEJAQAAAA==.',
Ce='Celesteus:BAAALgADCgkJFAAAAA==.',
Ch='Charis:BAAALgAECgYJCwAAAA==.Chel:BAAALgAECgEJAQAAAA==.Chigutotems:BAAALgAECgYJCwABLgAECgkJGwAPAGwWAA==.Chimmoku:BAABLgAFFH8IAAIBAAQJ6RA+GwA6AQABAAQJ6RA+GwA6AQABLgAFFAcJHQABAD4ZAA==.Choi:BAAALgAECgUJDwAAAA==.Chooq:BAAALgADCgIJAgAAAA==.Chozen:BAAALgAECgUJEAAAAA==.Chumlee:BAAALgAECgYJDgAAAA==.',
Ci='Cienna:BAAALgAECgYJDgAAAA==.Cigz:BAAALgADCgEJAQAAAA==.Cinch:BAAALgAECgIJAgAAAA==.',
Co='Colinferral:BAAALgAECgYJCAAAAA==.Coulee:BAAALgAECgQJCAABLgAFFAIJBQAWADQjAA==.Cowladin:BAAALgADCgUJBQAAAA==.',
Cr='Crakzkull:BAAALgAECgUJCwAAAA==.Croar:BAAALgAECgMJBAAAAA==.Cronicpain:BAAALgADCgkJCQAAAA==.',
Cu='Cuernuda:BAAALgAECgEJAQAAAA==.',
['Cä']='Cäntstandya:BAACLgAFFH8RAAMZAAQJVRgmGwDyAAAZAAMJnxcmGwDyAAAaAAMJmRhpYQDaAAAuAAQKfyMAAxoACAkvG1cSAKUCABoACAliGVcSAKUCABkABwkaHiYTAA4CAAAA.',
Da='Daiko:BAAALgAECgYJCQAAAA==.Daks:BAAALgAFFAIJAwAAAA==.Dargo:BAAALgAECgYJEwAAAA==.Darklucrezia:BAACLgAFFH8TAAMaAAUJjhypLwBJAQAaAAUJjhypLwBJAQAbAAIJNgJBNABIAAAuAAQKfy4AAxoACAn3H1EdAHECABoACAltH1EdAHECABsACAkOEeQlAPoBAAAA.Dazzlefraz:BAAALgAECgQJBAAAAA==.',
De='Demonklunter:BAAALgADCgYJEAAAAA==.Destructoid:BAAALgAECgEJAQAAAA==.',
Dg='Dgk:BAAALgAECgcJBwAAAA==.',
Di='Dicey:BAAALgADCgMJAwABLgAECgQJBwARAAAAAA==.',
Do='Dochunter:BAAALgAECgUJBQAAAA==.',
Dr='Dracarius:BAABLgAECn8VAAQcAAUJwxZSDwASAQAcAAQJwxZSDwASAQAHAAMJIwvgcwB7AAAdAAEJvQOkQwAdAAAAAA==.Drega:BAAALgAECgYJBwAAAA==.Droods:BAAALgAECgQJBQAAAA==.Drtypinkcake:BAABLgAECn8iAAIWAAkJ9wnMIwBUAQAWAAkJ9wnMIwBUAQAAAA==.Druskgar:BAABLgAECn8qAAMUAAkJMx8wLwBAAgAUAAkJMx8wLwBAAgAeAAcJ4A9vIgA9AQAAAA==.Dryad:BAABLgAECn8UAAIfAAUJNgw8RACQAAAfAAUJNgw8RACQAAAAAA==.',
Du='Duckster:BAAALgADCgYJBwAAAA==.Dunce:BAACLgAFFH8GAAIgAAIJdR/kOgCvAAAgAAIJdR/kOgCvAAAuAAQKfygAAiAACAnyIE4NAMMCACAACAnyIE4NAMMCAAAA.Durkk:BAABLgAECn87AAIeAAkJ9yFLBQDVAgAeAAkJ9yFLBQDVAgAAAA==.Durza:BAAALgAECgcJEAAAAA==.',
['Dä']='Dännydevito:BAAALgADCgQJBAAAAA==.',
Ea='Easyheal:BAAALgAECgUJBQAAAA==.',
Ed='Eduard:BAAALgAECgYJCQAAAA==.',
Ek='Eklipse:BAAALgAECgMJAwAAAA==.',
El='Elanthae:BAAALgAECgQJEQAAAA==.Elysia:BAAALgAECgEJAgAAAA==.',
Er='Erzulie:BAAALgAECgUJBAAAAA==.',
Es='Estara:BAABLgAECn81AAIfAAkJqwt3JQAhAQAfAAkJqwt3JQAhAQAAAA==.',
Et='Etali:BAABLgAECn8yAAILAAkJQBy3EABwAgALAAkJQBy3EABwAgAAAA==.',
Ex='Expired:BAAALgAECgEJAQAAAA==.',
Fa='Faite:BAAALgADCgUJBQAAAA==.Falorin:BAACLgAFFH8FAAIIAAIJXg7LnwCRAAAIAAIJXg7LnwCRAAAuAAQKfyAAAggACAkKFu9hALgBAAgACAkKFu9hALgBAAAA.Fanis:BAABLgAECn8mAAIbAAkJzRWUCQDYAQAbAAkJzRWUCQDYAQAAAA==.Fatherwhig:BAAALgAECgIJAwAAAA==.',
Fe='Fenrin:BAAALgAECgQJBwAAAA==.',
Fi='Fidis:BAAALgADCgkJCwAAAA==.Fistsofdeath:BAAALgADCggJCgAAAA==.Fistychub:BAAALgADCgEJAQAAAA==.',
Fl='Flashbang:BAAALgADCgEJAQAAAA==.Flashis:BAAALgAECggJEwAAAA==.Florago:BAABLgAECn8VAAIEAAUJnwZhIQCwAAAEAAUJnwZhIQCwAAAAAA==.',
Fr='Frakir:BAABLgAECn87AAQXAAkJ5xnMGACAAgAXAAkJ5xnMGACAAgAhAAMJRwp4LACLAAAJAAEJkAYjkwAjAAAAAA==.Fritzz:BAAALgAECgcJEgABLgAECgkJEwARAAAAAA==.Frog:BAAALgAECgIJBQAAAA==.',
Fu='Furrypaw:BAABLgAECn8uAAIgAAkJZiW+AQC8AwAgAAkJZiW+AQC8AwAAAA==.Fuzzyy:BAAALgAECgEJAQAAAA==.',
Fw='Fwapp:BAACLgAFFH8ZAAIOAAcJXh3OCwDtAQAOAAcJXh3OCwDtAQAuAAQKfxcAAg4ACAlrIcgLAL8CAA4ACAlrIcgLAL8CAAAA.',
Ga='Galvanize:BAAALgAECgEJBAABLgAECgcJHAAUALoWAA==.Galynisse:BAABLgAECn8xAAMiAAgJAhhCFAA5AgAiAAgJAhhCFAA5AgATAAMJ7A4eZQCZAAAAAA==.',
Ge='Gedorah:BAABLgAECn8fAAIjAAcJOByaAwDZAQAjAAcJOByaAwDZAQABLgAFFAQJFAAJAGMhAA==.',
Gh='Ghaspy:BAAALgAECgUJCgAAAA==.Ghoste:BAAALgADCgMJAwAAAA==.Ghrex:BAAALgAECgEJAQAAAA==.',
Gi='Gijaick:BAABLgAECn8vAAMCAAgJWBhPRQDJAQACAAgJWBhPRQDJAQADAAEJHg4AdAAxAAAAAA==.',
Gl='Glaivethrow:BAABLgAECn8bAAIPAAkJbBaQPgDKAQAPAAkJbBaQPgDKAQAAAA==.Glizzo:BAAALgAECgYJDAAAAA==.Gloam:BAAALgADCgUJBQAAAA==.Glueballs:BAAALgAECgEJAQABLgAECgcJDAARAAAAAA==.',
Go='Gochujjang:BAAALgAECgYJDQAAAA==.Goldhawk:BAAALgAECgMJAwAAAA==.Gotchá:BAAALgAECgEJBAAAAA==.Gotwiped:BAABLgAECn8WAAIUAAgJfRpxOgAUAgAUAAgJfRpxOgAUAgAAAA==.',
Gr='Grimgor:BAAALgAECgcJAQAAAA==.',
Ha='Hahaheals:BAAALgAECgMJBAAAAA==.Hakhar:BAAALgADCgMJAwAAAA==.Hanth:BAAALgADCgkJDAABLgAECgMJBAARAAAAAA==.Hatter:BAABLgAECn8pAAQPAAgJ4xUCQgC/AQAPAAgJ4xUCQgC/AQAWAAMJ+AsRWACGAAAQAAEJNRMmKwA0AAAAAA==.',
He='Healsus:BAAALgAECgMJAwAAAA==.Heimlish:BAAALgAECgEJAQAAAA==.Hellraiser:BAABLgAECn8pAAMUAAkJORgSNgAkAgAUAAkJWhcSNgAkAgAeAAcJaROVHwBVAQAAAA==.Hermione:BAAALgAECgYJDQAAAA==.Hexecution:BAAALgADCgIJAgAAAA==.',
Hi='Hiddendragon:BAAALgAECgEJAQAAAA==.',
Ho='Holydarkness:BAAALgAECgYJCgAAAA==.Holyhello:BAAALgAECgEJAQAAAA==.Holykilla:BAAALgAECgEJBQAAAA==.Holykiller:BAAALgAECgcJCgAAAA==.Hoofjob:BAAALgADCggJDgABLgAFFAUJDwAiAEccAA==.Hoplite:BAAALgADCgcJDgABLgAECggJEgARAAAAAA==.Hotot:BAAALgADCgMJAwAAAA==.Howlly:BAABLgAECn8ZAAIIAAkJfwyOYQC5AQAIAAkJfwyOYQC5AQAAAA==.',
Hu='Huffpuffle:BAAALgAECgUJCgAAAA==.',
['Hô']='Hôwl:BAABLgAECn8YAAIGAAcJwhBiRwBvAQAGAAcJwhBiRwBvAQAAAA==.',
Ic='Icdeathg:BAACLgAFFH8JAAIPAAMJ/QswaQCzAAAPAAMJ/QswaQCzAAAuAAQKfzEAAg8ACAksH/MZAHYCAA8ACAksH/MZAHYCAAAA.',
Ik='Iktaar:BAAALgAECgYJEQAAAA==.',
Il='Illidami:BAAALgADCgkJCwAAAA==.Illidamngirl:BAAALgADCgYJBgABLgAECgkJJwAMALwcAA==.',
Im='Imperius:BAACLgAFFH8VAAIVAAUJHBYHSQAWAQAVAAUJHBYHSQAWAQAuAAQKfyQAAhUACQmMJB0OAB0DABUACQmMJB0OAB0DAAAA.',
In='Ines:BAACLgAFFH8KAAIUAAMJWSEngwD+AAAUAAMJWSEngwD+AAAuAAQKfzoAAhQACQlrJBgLABMDABQACQlrJBgLABMDAAAA.Insomiax:BAAALgAECggJDwAAAA==.Insta:BAABLgAECn8rAAILAAcJzx3cIwA3AgALAAcJzx3cIwA3AgAAAA==.Inter:BAABLgAECn8vAAIeAAkJ9yE6BAALAwAeAAkJ9yE6BAALAwAAAA==.',
Ir='Iridi:BAAALgADCgEJAQAAAA==.Iritall:BAAALgADCgcJCwABLgAECgEJAgARAAAAAA==.',
It='Ithamburglar:BAAALgAECgQJBwAAAA==.',
Iz='Izureka:BAAALgADCgYJBgAAAA==.',
Ja='Jackidaytona:BAAALgAECgcJBwAAAA==.Jakaru:BAABLgAECn8bAAIgAAkJWRohEgCJAgAgAAkJWRohEgCJAgAAAA==.Jankadish:BAAALgAECgcJEwAAAA==.Jarre:BAACLgAFFH8GAAIGAAQJrggsDgAFAQAGAAQJrggsDgAFAQAuAAQKfygAAgYACAmzICIKAPMCAAYACAmzICIKAPMCAAAA.Jaspirian:BAAALgADCggJFAAAAA==.Jazzil:BAAALgADCgcJCgAAAA==.',
Jb='Jbaconcheese:BAAALgAECgEJAQAAAA==.',
Je='Jehm:BAAALgAECgIJAgABLgAECgMJAwARAAAAAA==.Jehmkin:BAAALgAECgEJAQAAAA==.Jehmothy:BAAALgAECgUJBQAAAA==.Jerome:BAAALgAECgEJAQAAAA==.',
Jo='Jotabop:BAAALgAECgQJBgAAAA==.',
Ju='Judgequota:BAAALgAFFAMJAwABLgAFFAUJEQAJACceAA==.Juggsgotcha:BAAALgAFFAIJAgAAAA==.Juicy:BAABLgAECn8kAAIZAAkJQReJDQBPAgAZAAkJQReJDQBPAgAAAA==.Juupiter:BAAALgAECgEJAQABLgAFFAIJBQAIAF4OAA==.',
Ka='Kabu:BAAALgAECgcJBwAAAA==.Kalia:BAABLgAECn8vAAMIAAkJ/xgVPgB/AgAIAAkJ/xgVPgB/AgAkAAMJUg/HDQCXAAAAAA==.Kalitra:BAAALgADCgMJAwABLgAECgkJLwAIAP8YAA==.Katatonik:BAAALgAECgQJBAAAAA==.Katharina:BAAALgAECgcJBwABLgAFFAEJAQARAAAAAA==.Katoumae:BAACLgAFFH8SAAIlAAUJNB1cBgBCAQAlAAUJNB1cBgBCAQAuAAQKfygAAiUACQkdIo4CAPkCACUACQkdIo4CAPkCAAAA.Katoumey:BAAALgAECgYJCgABLgAFFAUJEgAlADQdAA==.',
Ke='Keratin:BAABLgAECn8uAAImAAkJvSL/AwCVAgAmAAkJvSL/AwCVAgAAAA==.',
Kh='Khumi:BAABLgAECn8XAAIbAAgJYSCmEgCiAgAbAAgJYSCmEgCiAgABLgAFFAkJLQAVAD4mAA==.',
Ki='Kinan:BAABLgAECn82AAMaAAkJHSbXAQB1AwAaAAkJHSbXAQB1AwAbAAcJOx6kFwBxAgAAAA==.Kita:BAAALgAECggJEgABLgAECgkJAgARAAAAAA==.',
Kk='Kkaarrkk:BAAALgAECgUJCAAAAA==.',
Kr='Krindon:BAABLgAECn8nAAIWAAgJdBGtHQCJAQAWAAgJdBGtHQCJAQAAAA==.',
Ku='Kureiji:BAAALgADCgEJAQAAAA==.',
Ky='Kythin:BAAALgAECgEJAQABLgAECgkJLwAIAP8YAA==.',
La='Lacutis:BAAALgAECgEJBAAAAA==.Lanssolo:BAAALgAECggJEQAAAA==.Laww:BAAALgADCgcJCgAAAA==.',
Le='Lecroix:BAAALgADCgUJBQAAAA==.Leonus:BAAALgAECgMJAwABLgAECgIJAgARAAAAAA==.Lessana:BAAALgAECgQJDgAAAA==.Lethalforce:BAAALgADCgMJAwAAAA==.',
Li='Liandri:BAAALgADCgEJAgAAAA==.Lightchild:BAAALgADCggJCAAAAA==.Lightprivlge:BAAALgAECgcJDQABLgAECgcJHAAUALoWAA==.Lillith:BAAALgAECgMJAwAAAA==.Livewire:BAABLgAECn8VAAMJAAUJCyIkLQCMAQAJAAQJCyIkLQCMAQAXAAEJqhy0ugBTAAAAAA==.',
Lo='Lokohmojo:BAAALgAECgMJBAAAAA==.Lomponic:BAEBLgAECn8zAAISAAkJ4Rt3DwBiAgASAAkJ4Rt3DwBiAgAAAA==.Loomadin:BAAALgADCgYJCQAAAA==.Loranis:BAAALgAECgQJBgAAAA==.',
Lu='Lunethra:BAABLgAECn8rAAIaAAkJwhGAKwAGAgAaAAkJwhGAKwAGAgAAAA==.',
Ma='Mageaux:BAAALgAECgEJAgAAAA==.Magerag:BAACLgAFFH8JAAIIAAMJGBskeADuAAAIAAMJGBskeADuAAAuAAQKfy8AAwgACQlNIsMgAJgCAAgACQlNIsMgAJgCACQAAglAGkQVAHMAAAAA.Manamontana:BAACLgAFFH8ZAAMUAAcJtw9pMACcAQAUAAYJtw9pMACcAQAeAAEJAADKTQAAAAAuAAQKfxoAAhQACAn4H4AoAJgCABQACAn4H4AoAJgCAAAA.Marumo:BAAALgAECgMJBgAAAA==.',
Mc='Mcribz:BAACLgAFFH8bAAIUAAYJyCOrHwDnAQAUAAYJyCOrHwDnAQAuAAQKfyIAAhQACAl8IzIZAOUCABQACAl8IzIZAOUCAAAA.',
Me='Meelonusk:BAAALgAECgQJCAAAAA==.Mess:BAAALgAECgYJDAAAAA==.Messah:BAAALgAECgQJCgAAAA==.Messic:BAAALgADCgEJAQAAAA==.',
Mi='Michaelcoyle:BAACLgAFFH8IAAIaAAQJZQ2UQwAgAQAaAAQJZQ2UQwAgAQAuAAQKfzQAAhoACAnuHjwgAGICABoACAnuHjwgAGICAAAA.Midnightcrow:BAAALgADCgkJDwAAAA==.Milo:BAACLgAFFH8RAAILAAQJFiHiDgCIAQALAAQJFiHiDgCIAQAuAAQKfzcAAwsACQlFI0oGAPkCAAsACQlFI0oGAPkCAAoACAluHBQEALQCAAAA.Minlessu:BAAALgADCgEJAQAAAA==.Miorine:BAAALgAECgEJAgAAAA==.Mishra:BAAALgAECgUJBQAAAA==.Mitra:BAABLgAECn86AAIYAAkJuSK6AAApAwAYAAkJuSK6AAApAwAAAA==.',
Mo='Moesko:BAACLgAFFH8HAAIGAAMJzQuRRgCXAAAGAAMJzQuRRgCXAAAuAAQKfxUAAgYACQlwEgs+AJgBAAYACQlwEgs+AJgBAAAA.Mof:BAAALgADCgEJAQAAAA==.Mohawkk:BAAALgAECgQJBQAAAA==.Monktup:BAAALgAECgYJCwAAAA==.Monnehbaggs:BAABLgAECn8wAAMiAAkJTxxuDQCUAgAiAAgJbRtuDQCUAgATAAgJpR3/DQB7AgAAAA==.Mortalidad:BAAALgADCgQJBAAAAA==.',
Mu='Muin:BAAALgAECgEJAQAAAA==.Murdersamich:BAAALgAECgQJCwAAAA==.',
My='Mybigcrits:BAAALgAECgYJDAAAAA==.Myraghor:BAAALgADCgYJBgAAAA==.',
['Mà']='Màevë:BAAALgAECgEJAgAAAA==.',
Na='Nairdax:BAAALgADCgEJAQAAAA==.Nalmec:BAABLgAECn8hAAILAAYJPQhbXADfAAALAAYJPQhbXADfAAAAAA==.Nama:BAAALgADCgcJFAAAAA==.Naysayre:BAABLgAECn8wAAIPAAgJ4AdDhwAOAQAPAAgJ4AdDhwAOAQAAAA==.',
Ne='Nebody:BAAALgAECgYJDwAAAA==.Necriss:BAABLgAECn8sAAIVAAkJUxBxYgCpAQAVAAkJUxBxYgCpAQAAAA==.Nevereven:BAAALgAECgEJAQAAAA==.',
Ni='Nightkilla:BAAALgAECgEJAwAAAA==.Nike:BAAALgAECggJEAAAAA==.Nilowin:BAABLgAECn82AAIBAAkJCxHQFgDhAQABAAkJCxHQFgDhAQAAAA==.',
No='Nokaj:BAAALgAECgEJAgAAAA==.Noshards:BAAALgAECgcJDQAAAA==.Notericdh:BAAALgAECgYJEwAAAA==.',
Og='Oghom:BAAALgADCgcJCgAAAA==.',
Oh='Ohnoitzgumby:BAABLgAECn8cAAMUAAcJuha0awCLAQAUAAcJrBa0awCLAQAmAAMJoBJPFABOAAAAAA==.',
Om='Omiko:BAAALgAECgIJAgAAAA==.',
Op='Opeep:BAAALgADCgcJGQAAAA==.',
Or='Orah:BAAALgADCgEJAQAAAA==.',
Os='Osos:BAAALgAECgYJEAAAAA==.',
Pa='Paladimdab:BAAALgAECgQJBQAAAA==.Papachance:BAABLgAECn8aAAIIAAgJhghinQA8AQAIAAgJhghinQA8AQAAAA==.Papafrank:BAAALgAECgYJCgAAAA==.Paradis:BAAALgADCgcJBwAAAA==.Pazuzu:BAAALgADCgYJBgAAAA==.',
Pe='Peepo:BAAALgAECgEJAQAAAA==.',
Pi='Pinga:BAACLgAFFH8FAAIiAAMJjgpBMwC5AAAiAAMJjgpBMwC5AAAuAAQKfyEABCIACQm6H2MFADIDACIACQm6H2MFADIDABMAAgn6HHpeAFwAABIAAQmZDsqGADAAAAEuAAUUBAkJAB0AeBYA.Pinkberry:BAAALgAECgQJBAAAAA==.Pintcube:BAAALgADCgYJCAAAAA==.',
Pl='Pljeskavica:BAAALgAECgYJBwAAAA==.Plox:BAAALgAECgMJAwAAAA==.',
Po='Port:BAABLgAECn8wAAIGAAkJ8R5dDAD6AgAGAAkJ8R5dDAD6AgAAAA==.Potroastjr:BAAALgADCgEJAgABLgAECgEJAQARAAAAAA==.',
Pr='Preposition:BAAALgAECgcJBwAAAA==.Primordus:BAAALgADCgUJBQAAAA==.Profiler:BAAALgAECgcJCgAAAA==.Protocol:BAAALgAECgMJAwAAAA==.Prïestess:BAAALgAECgcJDAAAAA==.',
Ps='Pseriph:BAABLgAECn8ZAAIDAAcJ3BZrCwAKAgADAAcJ3BZrCwAKAgAAAA==.',
Ra='Radamantis:BAAALgAECgQJBwAAAA==.Raenon:BAAALgAECgEJAQAAAA==.Raggnar:BAACLgAFFH8UAAIJAAQJYyEQFAB0AQAJAAQJYyEQFAB0AQAuAAQKfzEAAgkACQmVIW0HAOMCAAkACQmVIW0HAOMCAAAA.Ragingwaters:BAAALgADCgYJCAABLgAECgIJBgARAAAAAA==.Ranvir:BAAALgAECgIJAgAAAA==.Raun:BAABLgAECn87AAMVAAkJBiNxCQAbAwAVAAkJBiNxCQAbAwAOAAMJJBEvcgCzAAAAAA==.',
Re='Regnarr:BAAALgADCgEJAQAAAA==.Rehgar:BAAALgAFFAEJAQAAAA==.Relaire:BAABLgAECn9EAAIaAAkJTxTnMQAQAgAaAAkJTxTnMQAQAgAAAA==.Remenissions:BAAALgAECgEJAQAAAA==.Resonate:BAAALgAFFAIJAwAAAA==.',
Ri='Rikane:BAAALgADCgcJDAABLgADCgcJEgARAAAAAA==.Rikenji:BAAALgAECgEJAQABLgAFFAIJBQAIAF4OAA==.Riku:BAABLgAECn82AAIlAAkJvSC/AgDyAgAlAAkJvSC/AgDyAgAAAA==.',
Ro='Rock:BAAALgAECgcJEgAAAA==.Rocks:BAAALgAECgEJAQAAAA==.Rockyrag:BAAALgAECgUJBQAAAA==.Roguey:BAABLgAECn8sAAMnAAkJuQ8qDABoAQAnAAcJlBEqDABoAQABAAcJ/wyJKABOAQAAAA==.Roots:BAAALgAECgEJCAAAAA==.',
Ru='Rulethrefour:BAAALgAECgQJCAABLgAECgcJHAAUALoWAA==.',
Ry='Ryveri:BAABLgAECn8lAAILAAkJDxlcHQACAgALAAkJDxlcHQACAgAAAA==.',
Sa='Sablehide:BAABLgAECn81AAIHAAkJ4Bm3EQBUAgAHAAkJ4Bm3EQBUAgAAAA==.Sanaron:BAAALgADCgIJAgAAAA==.Sanaty:BAAALgAFFAIJBAAAAA==.Sarnak:BAAALgADCgMJAwAAAA==.Saryn:BAAALgAECgYJDwAAAA==.Satanz:BAAALgADCgIJAgAAAA==.Sathanus:BAAALgAECgUJEwAAAA==.Sathir:BAAALgADCgMJAwAAAA==.',
Se='Searate:BAAALgADCgcJEgAAAA==.Seaside:BAACLgAFFH8PAAIUAAMJ/iX3HAAvAQAUAAMJ/iX3HAAvAQAuAAQKfxgAAxQABwk9JepDAPQBABQABwk9JepDAPQBAB4AAgmEC+8/AE4AAAAA.Secrett:BAABLgAECn8cAAMBAAcJKBXEJABrAQABAAcJKBXEJABrAQAnAAEJew63KAAwAAAAAA==.Sephyxia:BAABLgAECn8vAAIeAAkJdBo3DgAlAgAeAAkJdBo3DgAlAgAAAA==.Serryon:BAAALgADCgIJAgAAAA==.',
Sf='Sfora:BAAALgAECgUJBQAAAA==.',
Sh='Shadowreaper:BAAALgADCgYJBQAAAA==.Shadowwzz:BAAALgADCgEJAQAAAA==.Shocknezz:BAAALgAECgYJCAAAAA==.Shockwaves:BAAALgAECgEJAQAAAA==.Shoçknezz:BAAALgAECgMJBQAAAA==.',
Si='Silverwolf:BAABLgAECn9GAAIhAAkJ/SChAgDrAgAhAAkJ/SChAgDrAgAAAA==.Simplyunlock:BAACLgAFFH8YAAMCAAUJIgwXXAALAQACAAQJIgwXXAALAQAEAAEJAABrMAAAAAAuAAQKfycAAwIACQnzE94zAAgCAAIACQnzE94zAAgCAAMAAgnnBZVmAEMAAAAA.Simplyvoided:BAAALgAECgQJBgAAAA==.Sinfulcynic:BAAALgADCgQJBQAAAA==.Sinverguenza:BAAALgAECgMJBQAAAA==.Sizzlechop:BAABLgAECn8uAAMUAAkJ/g+ihQBWAQAUAAgJ7QqihQBWAQAeAAMJrBZONADEAAAAAA==.',
Sk='Skizzak:BAAALgADCgQJBAABLgAFFAYJGwAUAMgjAA==.Skweeks:BAAALgAECgMJBAAAAA==.',
Sm='Smelvin:BAABLgAECn8cAAIJAAkJ8xlsFgBmAgAJAAkJ8xlsFgBmAgABLgAECgQJCAARAAAAAA==.Smoko:BAAALgAECgIJAgABLgAECgUJBQARAAAAAA==.',
Sn='Snailslolol:BAAALgAECgcJCgAAAA==.Snakey:BAECLgAFFH8aAAMHAAUJGgmCOgDaAAAHAAQJGgmCOgDaAAAcAAIJ1wLjDwA5AAAuAAQKfywAAwcACAmLGD4aAPkBAAcACAmLGD4aAPkBABwABgl5BHkmAO8AAAAA.',
So='Solara:BAABLgAECn8hAAQSAAkJMRiEFgAVAgASAAkJMRiEFgAVAgATAAEJQAIShwApAAAiAAEJXgKYXgAkAAAAAA==.Soleill:BAAALgAECgcJBwAAAA==.Sondan:BAAALgADCgMJAwAAAA==.Songs:BAAALgAECgEJAQABLgAECgYJGAANAP8gAA==.',
Sp='Spellpowa:BAAALgAECgYJDgAAAA==.',
Sq='Squirtin:BAAALgAECgIJAgAAAA==.',
Ss='Ssminion:BAAALgAECgMJBgAAAA==.',
St='Stalath:BAAALgAECgQJBQAAAA==.Stormwing:BAABLgAECn8fAAMJAAgJiBnxJQC3AQAJAAgJiBnxJQC3AQAXAAEJMRZ7yABAAAAAAA==.Strecagosa:BAAALgAECgYJDQAAAA==.',
Su='Sumarr:BAAALgAECgYJBgABLgAECgcJBwARAAAAAA==.',
Sv='Svenn:BAAALgAECgYJBgAAAA==.',
Sw='Swiftstrike:BAAALgADCgUJBQAAAA==.',
Sy='Sybelissa:BAAALgAECgMJAwABLgAECgcJCgARAAAAAA==.Synni:BAAALgADCgEJAQAAAA==.',
['Sÿ']='Sÿnÿster:BAAALgAECgQJBQABLgAFFAUJEwAaAI4cAA==.',
Ta='Talron:BAAALgAECgUJCAAAAA==.Tastytay:BAAALgADCgMJAwAAAA==.Tatertots:BAABLgAECn8yAAMmAAkJFCCZAgDaAgAmAAkJFCCZAgDaAgAUAAMJ8hON7ACmAAAAAA==.',
Te='Tea:BAABLgAECn8xAAIaAAkJgCWkAwBUAwAaAAkJgCWkAwBUAwAAAA==.Teal:BAAALgAECgMJAwAAAA==.Templyn:BAABLgAECn8vAAMUAAkJWxRiVgC/AQAUAAkJgQ5iVgC/AQAeAAgJCRb9GQCMAQAAAA==.Templÿn:BAAALgADCgIJAgABLgAECgkJLwAUAFsUAA==.Tenebrarum:BAABLgAECn8bAAIaAAgJGQ0xVwBjAQAaAAgJGQ0xVwBjAQAAAA==.Testorooni:BAABLgAECn8ZAAIaAAcJkBgpMwDjAQAaAAcJkBgpMwDjAQAAAA==.',
Th='Thakodi:BAAALgAECgQJBAAAAA==.Thannos:BAAALgADCgEJAQAAAA==.Tharvan:BAAALgADCgcJDAAAAA==.Thavok:BAAALgAECgEJAQAAAA==.Thedeadman:BAABLgAECn8kAAIUAAkJEyJDIwB3AgAUAAkJEyJDIwB3AgAAAA==.Thepriestg:BAAALgAECgEJAQAAAA==.Thiccksilver:BAAALgADCgcJBwABLgAFFAQJDwACAAUWAA==.Thompson:BAABLgAECn8VAAIUAAcJuxSKkQBAAQAUAAcJuxSKkQBAAQAAAA==.Thunderflaps:BAAALgAECgUJCQAAAA==.Thyrus:BAACLgAFFH8JAAIdAAQJeBZ4FgAlAQAdAAQJeBZ4FgAlAQAuAAQKfzUAAx0ACQk9In4DAAwDAB0ACQk9In4DAAwDABwAAQmqAvtEACMAAAAA.',
Ti='Tirna:BAABLgAECn84AAIjAAkJng5WBACtAQAjAAkJng5WBACtAQAAAA==.',
To='Toebot:BAAALgAECgEJAQAAAA==.Toggle:BAAALgAECgEJAQAAAA==.Tomsellock:BAABLgAECn8WAAMEAAcJjhBuBwDcAQAEAAcJjhBuBwDcAQACAAEJugM+LAEmAAAAAA==.Tonari:BAAALgAECgEJAQABLgAECgYJEAARAAAAAA==.Torvi:BAAALgADCgMJAwAAAA==.',
Tr='Transmørtuus:BAAALgAECgQJCQAAAA==.Treehug:BAAALgAECggJEwAAAA==.Triple:BAAALgAECgQJBwABLgAECgYJEAARAAAAAA==.Trolleonne:BAAALgAECgIJAgAAAA==.',
Tu='Tullen:BAEBLgAECn81AAITAAkJjRH2IQCuAQATAAkJjRH2IQCuAQAAAA==.Turanos:BAABLgAECn8VAAIoAAUJ0gp9MgCWAAAoAAUJ0gp9MgCWAAAAAA==.',
Tw='Tweyen:BAAALgAECgEJAQAAAA==.Twistedbael:BAAALgAECgUJBQAAAA==.',
Ty='Tyindaris:BAAALgAECgQJCgAAAA==.Tyloregeth:BAABLgAECn8sAAISAAgJphTZKACHAQASAAgJphTZKACHAQAAAA==.',
['Tè']='Tèmplyn:BAAALgADCgEJAQABLgAECgkJLwAUAFsUAA==.',
['Té']='Témplýn:BAAALgADCgEJAQABLgAECgkJLwAUAFsUAA==.',
['Të']='Tëmplýn:BAAALgAECgIJAgABLgAECgkJLwAUAFsUAA==.',
Ul='Ulfrunn:BAAALgADCgYJBgAAAA==.Ultrachad:BAACLgAFFH8jAAIUAAgJYxnNDQBgAgAUAAgJYxnNDQBgAgAuAAQKfx4AAhQACAlNIwUUAAMDABQACAlNIwUUAAMDAAAA.',
Um='Umami:BAABLgAECn8gAAILAAYJ+RhzSgB7AQALAAYJ+RhzSgB7AQAAAA==.',
Un='Unggoy:BAACLgAFFH8kAAQbAAgJHR38AgAkAgAbAAgJ9Bv8AgAkAgAZAAQJyRRgEQA5AQAaAAIJsRmJcwCpAAAuAAQKfygAAxsACQkhJrsBAKYDABsACQkhJrsBAKYDABoAAQnFJffvAGsAAAAA.Unhollowed:BAAALgAECgIJBAAAAA==.Unholywaters:BAAALgAECgIJBgAAAA==.',
Ur='Urianna:BAAALgAECgYJCwAAAA==.',
Va='Vaelthirion:BAABLgAECn8nAAIIAAgJYxZbTgDtAQAIAAgJYxZbTgDtAQAAAA==.Vahidamus:BAAALgAECggJCwAAAA==.Valkaryon:BAAALgAECgcJCgABLgAFFAIJAwARAAAAAA==.Valmirax:BAAALgADCggJEgAAAA==.Valton:BAABLgAECn9bAAIVAAgJnxIBZwCfAQAVAAgJnxIBZwCfAQAAAA==.',
Ve='Vegetation:BAAALgAECgQJBwAAAA==.Velenestus:BAAALgAECgMJBgAAAA==.Verses:BAAALgADCgEJAQAAAA==.',
Vi='Vizsla:BAAALgAECgEJAQAAAA==.',
Wa='Wackaman:BAABLgAECn8nAAIMAAkJvBwhCQBhAgAMAAkJvBwhCQBhAgAAAA==.Waffleshirt:BAAALgAECgcJBwAAAA==.Warpig:BAAALgAECgYJEQAAAA==.Wasps:BAAALgAECgYJEQAAAA==.',
We='Wegmaniac:BAAALgADCgYJCAAAAA==.Welastrexa:BAAALgADCgUJBQABLgAECgIJBgARAAAAAA==.',
Wi='Wickedclöwn:BAAALgADCgMJAwAAAA==.Winchester:BAAALgADCgIJAgAAAA==.Windhorn:BAAALgAECgYJEAAAAA==.Winds:BAABLgAECn8YAAINAAYJ/yBoFwAqAgANAAYJ/yBoFwAqAgAAAA==.',
Wn='Wntrizcoming:BAAALgADCgMJBQAAAA==.',
Wo='Wolfquota:BAACLgAFFH8RAAIJAAUJJx62HQAoAQAJAAUJJx62HQAoAQAuAAQKfyQAAwkACAmCIkkJAP4CAAkACAmCIkkJAP4CACEABAntE08eAOkAAAAA.Wolftime:BAAALgADCgUJBQAAAA==.Wombaa:BAACLgAFFH8YAAMUAAUJoiUIMQCaAQAUAAUJoiUIMQCaAQAmAAIJPR6dGQCyAAAuAAQKfxwAAhQACAleJGEKAEgDABQACAleJGEKAEgDAAAA.Woolybully:BAAALgAECgEJAQABLgAECgYJBwARAAAAAA==.',
Wr='Wrathbolt:BAAALgAECgEJAgABLgAFFAQJCgATAGAOAA==.Wrathmo:BAACLgAFFH8HAAINAAQJehkAEQAvAQANAAQJehkAEQAvAQAuAAQKfyUAAw0ACAljHBUUABgCAA0ABwlpHhUUABgCACkABwkdCg5AAPgAAAEuAAUUBAkKABMAYA4A.Wrathp:BAABLgAFFH8KAAITAAQJYA6iGADwAAATAAQJYA6iGADwAAAAAA==.Wrolie:BAAALgADCgMJAwAAAA==.',
['Wê']='Wêêdyys:BAAALgADCgMJBAAAAA==.',
Xy='Xyr:BAAALgAECgEJAQABLgAECgkJQAASAPUYAA==.',
Ya='Yamiamigo:BAAALgAECgEJAgAAAA==.',
Yo='Yonah:BAAALgAECgEJAQAAAA==.Yougotsniped:BAAALgADCgEJAQAAAA==.',
Za='Zandalia:BAAALgAECgMJAwAAAA==.Zark:BAEALgAECgEJAQABLgAECgkJGQAXAHsWAA==.',
Ze='Zemphoths:BAAALgAECgcJCgAAAA==.',
Zo='Zoa:BAAALgADCgYJBgAAAA==.Zolton:BAAALgADCgMJAwAAAA==.Zornak:BAABLgAECn8ZAAICAAUJlA2lugDUAAACAAUJlA2lugDUAAAAAA==.',
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
