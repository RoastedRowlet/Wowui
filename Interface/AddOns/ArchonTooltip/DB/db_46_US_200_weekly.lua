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

local lookup = {'Mage-Frost','Monk-Brewmaster','Druid-Restoration','DeathKnight-Unholy','Mage-Arcane','Shaman-Restoration','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Warlock-Affliction','Shaman-Enhancement','Priest-Holy','Warlock-Destruction','Warlock-Demonology','DeathKnight-Blood','Unknown-Unknown','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Frost','DemonHunter-Devourer','Paladin-Protection','DemonHunter-Havoc','Shaman-Elemental','DemonHunter-Vengeance','Priest-Discipline','Hunter-BeastMastery','Priest-Shadow','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','Paladin-Holy','Evoker-Augmentation',}
local provider = {region='US',realm='Smolderthorn',name='US',type='weekly',zone=46,date='2026-06-13',data={Ac='Achoo:BAABLgAECn8WAAIBAAcJ4gQR1QDmAAABAAcJ4gQR1QDmAAAAAA==.Acorn:BAAALgADCgMJBAAAAA==.',
Ai='Aitnd:BAAALgAECgMJAwAAAA==.Aitns:BAAALgADCgUJBQAAAA==.',
Ak='Akabara:BAAALgAECgQJBwAAAA==.',
Al='Alatyr:BAAALgAECgUJBQABLgAECgkJGQACAHEYAA==.Alduinn:BAAALgADCggJEAAAAA==.',
Am='Amilde:BAAALgAECgkJEQABLgAFFAMJCAADAGkSAA==.Amongor:BAABLgAECn8YAAIEAAYJ3h95UAAAAgAEAAYJ3h95UAAAAgAAAA==.',
An='Anarisa:BAABLgAECn9gAAMBAAkJQyD4DwD5AgABAAkJQyD4DwD5AgAFAAUJcRGGCwAeAQAAAA==.',
Aq='Aquatide:BAAALgAECgYJBgABLgAFFAgJIQAGAAQeAA==.',
Ar='Arcaz:BAAALgAECgEJAQAAAA==.Artoria:BAAALgADCgkJCwAAAA==.',
At='Athorama:BAAALgAECgUJCwAAAA==.Atra:BAAALgAECgEJAQAAAA==.',
Av='Avelise:BAABLgAECn8UAAIBAAcJkBelaQADAgABAAcJkBelaQADAgABLgAFFAMJCAADAGkSAA==.Averse:BAACLgAFFH8YAAIEAAQJzh8qRgBiAQAEAAQJzh8qRgBiAQAuAAQKfzUAAgQACQk0HjcYALMCAAQACQk0HjcYALMCAAAA.',
Az='Azazygos:BAAALgAECgMJAwAAAA==.',
Ba='Baeloth:BAAALgADCgcJDAAAAA==.Barkknight:BAEALgAECgkJBQABLgAFFAQJEwAHAMMQAA==.Barley:BAAALgAECgUJBQAAAA==.Bauce:BAAALgAECgYJBgAAAA==.',
Be='Bearretheon:BAAALgADCgEJAQAAAA==.Benchtally:BAAALgAECgYJDAAAAA==.Bepizo:BAACLgAFFH8QAAMIAAUJpx/LKgADAQAIAAMJHxrLKgADAQAJAAMJyh3hKgC4AAAuAAQKf0YAAwkACQndJCgKAEYCAAkABgnSIigKAEYCAAgABwmzItUpABICAAAA.',
Bl='Bluetide:BAACLgAFFH8hAAIGAAgJBB6kAgCwAgAGAAgJBB6kAgCwAgAuAAQKfykAAgYACQmOJn8AAOEDAAYACQmOJn8AAOEDAAAA.',
Br='Brokemav:BAABLgAECn8vAAIKAAcJESGWAgCTAgAKAAcJESGWAgCTAgAAAA==.Brooklin:BAABLgAECn8yAAIBAAkJnh7dKwDDAgABAAkJnh7dKwDDAgAAAA==.',
Bu='Busky:BAABLgAECn8lAAMGAAkJAhVaKwDfAQAGAAkJAhVaKwDfAQALAAcJkhFFFwBMAQAAAA==.',
Ca='Carboncredit:BAABLgAECn8iAAILAAkJrRAICgAyAgALAAkJrRAICgAyAgAAAA==.Cassiopea:BAABLgAECn8ZAAIMAAgJ7ho9GAAHAgAMAAgJ7ho9GAAHAgAAAA==.Caysia:BAABLgAFFH8IAAIDAAMJaRI1QACrAAADAAMJaRI1QACrAAAAAA==.',
Ce='Cellcept:BAABLgAECn8XAAINAAUJGh7VDQBbAQANAAUJGh7VDQBbAQAAAA==.',
Ch='Chareth:BAABLgAECn8oAAIBAAkJNgpqbwCYAQABAAkJNgpqbwCYAQAAAA==.Charlee:BAAALgADCgcJBwAAAA==.Chaunticleer:BAAALgAECgcJCwAAAA==.Chesumadre:BAAALgADCgMJBAAAAA==.Chinchillada:BAABLgAECn8hAAIBAAgJLxSYWADQAQABAAgJLxSYWADQAQAAAA==.',
Ci='Cinderfal:BAAALgAECgEJAgAAAA==.',
Cl='Claggor:BAAALgAECgMJAwAAAA==.',
Co='Coldbrewed:BAAALgAECgYJBgAAAA==.Cowladin:BAAALgADCgYJBgABLgAECggJHwAOADcfAA==.',
Cr='Crossover:BAAALgADCgYJBgAAAA==.',
['Cà']='Càss:BAAALgAECgQJBQABLgAECggJGQAMAO4aAA==.',
Da='Dabajabaza:BAABLgAECn80AAIPAAkJ1QqRIgA8AQAPAAkJ1QqRIgA8AQAAAA==.Dabergerak:BAACLgAFFH8JAAIIAAMJXCHJLAD5AAAIAAMJXCHJLAD5AAAuAAQKfysAAggACQmcJT4DADgDAAgACQmcJT4DADgDAAAA.Daenys:BAAALgAECgMJAwABLgAFFAgJLAAKAA0bAA==.Daggart:BAAALgAECgkJDgAAAA==.Dagrimreaper:BAAALgADCgcJBgABLgAECgcJEAAQAAAAAA==.Daila:BAAALgAECgEJAQAAAA==.Dakrus:BAACLgAFFH8FAAIRAAMJmg3NIADNAAARAAMJmg3NIADNAAAuAAQKfyUAAxIACQkwGVIgACMCABIACAmpFlIgACMCABEABgk9DigsAEIBAAAA.Dankestacorn:BAAALgADCggJCQAAAA==.Darthßsaber:BAAALgADCgUJBQAAAA==.Dax:BAAALgADCgYJBgAAAA==.',
De='Deadazz:BAABLgAECn8aAAMTAAcJCQ0vFQAuAQATAAcJCQ0vFQAuAQAPAAYJCgRDQgCDAAABLgAFFAUJCgAOALIPAA==.Deadputz:BAAALgAECggJEwABLgAFFAMJBwAUAFYaAA==.Deeiinnduh:BAAALgAECgYJBgAAAA==.Dein:BAAALgAECgcJEQAAAA==.Dejanira:BAABLgAECn8gAAIDAAkJzhHkPwCQAQADAAkJzhHkPwCQAQAAAA==.Demonslayerr:BAAALgADCgQJBAAAAA==.Demotope:BAAALgADCgcJDAABLgAECgYJDAAQAAAAAA==.',
Di='Diddily:BAABLgAECn8VAAMVAAgJWxUTHwAQAQAVAAgJWxUTHwAQAQAHAAIJ7QOlvAEiAAAAAA==.Diesverdi:BAAALgAECgMJAwAAAA==.Dirtylilskin:BAAALgADCgkJHQAAAA==.',
Do='Dookie:BAAALgAECgQJBAAAAA==.',
Dr='Draconae:BAABLgAECn8bAAIWAAYJWQd0PQC8AAAWAAYJWQd0PQC8AAAAAA==.Dracotope:BAAALgAECgYJDAAAAA==.Dragonjoy:BAABLgAECn8kAAIPAAkJORZ8FgCzAQAPAAkJORZ8FgCzAQAAAA==.Drathier:BAAALgAECgIJAgAAAA==.Dridarok:BAABLgAECn8gAAIIAAkJqQwLLQCdAQAIAAkJqQwLLQCdAQAAAA==.',
['Dâ']='Dâwn:BAAALgAECggJEAAAAA==.',
Ei='Eighttyhd:BAAALgADCgQJBAAAAA==.Eightyhd:BAAALgADCgIJAgAAAA==.Eirny:BAAALgAECgMJBAAAAA==.',
El='Element:BAAALgADCgEJAQABLgAFFAUJEAAIAKcfAA==.Elise:BAABLgAECn8kAAMNAAkJQhckCQAvAgANAAgJzBckCQAvAgAKAAgJARH4DgBBAQAAAA==.Elstrid:BAABLgAECn8fAAMOAAgJNx+SLwAYAgAOAAgJNx+SLwAYAgANAAEJAAAuVAAAAAAAAA==.',
Er='Erzaflame:BAAALgADCgEJAQAAAA==.',
Eu='Euphoria:BAAALgAECgMJAwABLgAECgkJNAAXACMlAA==.',
Ev='Evochre:BAAALgAECgUJCQAAAA==.',
Fa='Faelgalus:BAAALgAECgIJAgAAAA==.Faerine:BAAALgADCgcJBwAAAA==.Fantasy:BAABLgAECn80AAIXAAkJIyUiAwA8AwAXAAkJIyUiAwA8AwAAAA==.',
Fe='Felbourn:BAACLgAFFH8IAAIWAAMJvxmOFgDpAAAWAAMJvxmOFgDpAAAuAAQKfyAABBYACQlkIY4IANkCABYACAmJIY4IANkCABgAAgktFo0hAIwAABQAAgm7CW/MAF0AAAAA.Fendraim:BAAALgAECgYJCwABLgAECgcJEQAQAAAAAA==.',
Fi='Figurefour:BAAALgAECgkJDwAAAA==.',
Fo='Foedris:BAAALgADCgUJBQAAAA==.Forste:BAAALgAECgUJBQAAAA==.Foxfire:BAAALgAECgQJCAAAAA==.',
Fr='Frailboosy:BAACLgAFFH8OAAIHAAQJ0RZkPwAnAQAHAAQJ0RZkPwAnAQAuAAQKf1sAAgcACQkYIqILAAYDAAcACQkYIqILAAYDAAAA.Fri:BAAALgADCgkJCQAAAA==.Frigamortis:BAAALgAECgYJEQAAAA==.',
Ge='Gemini:BAAALgAECgQJBAAAAA==.',
Gi='Gilferno:BAAALgAECgQJBAAAAA==.',
Gl='Glitz:BAABLgAFFH8FAAIBAAUJawQvdgD0AAABAAUJawQvdgD0AAABLgAFFAYJEQAZAMwGAA==.',
Gn='Gnarfok:BAAALgAECgQJDwAAAA==.',
Go='Goopster:BAAALgADCgcJCQAAAA==.',
Gr='Graamps:BAAALgAECgYJDQAAAA==.Gravedigger:BAACLgAFFH8QAAMPAAQJuBsnFQA8AQAPAAQJuBsnFQA8AQATAAEJZACuLAAoAAAuAAQKfzQAAg8ACQncH+0JAHMCAA8ACQncH+0JAHMCAAAA.',
Gu='Gunde:BAAALgAECgkJBQAAAA==.Gust:BAAALgAECgQJDwAAAA==.',
Ha='Hatredx:BAAALgADCgIJAgAAAA==.',
He='Heisenberg:BAAALgAECgQJCAABLgAFFAQJDwAaAHsRAA==.',
Ho='Holywagyu:BAAALgAECgYJBgAAAA==.',
Hy='Hyllinia:BAAALgADCgEJAQAAAA==.Hyõrinmaru:BAAALgAECgMJAwAAAA==.',
Ih='Iheal:BAAALgAECgEJAQAAAA==.',
In='Inarios:BAABLgAECn8qAAQZAAkJhxsrDQCYAgAZAAgJ/h0rDQCYAgAbAAQJlhVzPQAZAQAMAAEJtwz9cwAkAAAAAA==.Inshape:BAAALgAECgYJEwAAAA==.',
Ir='Ironnman:BAAALgAECgEJAQABLgAECgkJGQACAHEYAA==.Ironnmonk:BAABLgAECn8ZAAQCAAkJcRiBGwAnAgACAAkJcRiBGwAnAgAcAAEJihEZmgAyAAAdAAEJUgQwdQAcAAAAAA==.',
Ja='Javlin:BAAALgAECgYJEAAAAA==.',
Jo='Joltarin:BAAALgAECgEJAQABLgAECggJHwAOADcfAA==.',
Ju='Jujufya:BAAALgAECgIJAgABLgAECgcJEAAQAAAAAA==.Jujujab:BAAALgADCgMJAwABLgAECgcJEAAQAAAAAA==.Jujukni:BAAALgAECgUJDQABLgAECgcJEAAQAAAAAA==.Jujumon:BAAALgAECgcJEAAAAA==.Jujuzul:BAAALgADCgUJBgABLgAECgcJEAAQAAAAAA==.Justimp:BAACLgAFFH8GAAIOAAMJTQglhQC2AAAOAAMJTQglhQC2AAAuAAQKfyQAAg4ACQl4FDRCANQBAA4ACQl4FDRCANQBAAAA.',
Ka='Kanon:BAABLgAECn8WAAIeAAkJBxNOEgDCAQAeAAkJBxNOEgDCAQAAAA==.Kanook:BAAALgAECgMJAwAAAA==.Karlek:BAABLgAFFH8GAAMfAAMJ2gSfNwCHAAAfAAMJ2gSfNwCHAAAHAAEJ6AF1yQAvAAAAAA==.',
Ke='Kelox:BAAALgAECgEJAQAAAA==.',
Ki='Kikily:BAAALgADCgkJCQAAAA==.',
Ko='Konsistency:BAABLgAECn8fAAIUAAcJlA6icgBNAQAUAAcJlA6icgBNAQAAAA==.Konviction:BAABLgAECn8fAAMHAAkJ/RFyhwBeAQAHAAkJ/RFyhwBeAQAVAAIJZwJXWAAcAAAAAA==.Korellon:BAAALgADCgMJAwAAAA==.',
Kr='Kreel:BAAALgADCggJCAAAAA==.Krogg:BAAALgADCgcJBwAAAA==.',
La='Lalana:BAABLgAECn8iAAIaAAgJOA5EXACMAQAaAAgJOA5EXACMAQAAAA==.Lan:BAAALgAECgcJDQAAAA==.Landin:BAAALgAECgcJBwAAAA==.',
Li='Liari:BAECLgAFFH8FAAIBAAMJBwQUkAC4AAABAAMJBwQUkAC4AAAuAAQKfxwAAgEACAkrCrSPAFUBAAEACAkrCrSPAFUBAAEuAAUUBAkTAAcAwxAA.Libra:BAAALgADCgEJAQAAAA==.Lilith:BAACLgAFFH8RAAMZAAYJzAbHCABRAQAZAAYJzAbHCABRAQAbAAQJcwkoJwC7AAAuAAQKfyEAAxkACQmpGG4SACECABkACAk0GW4SACECABsABwmVHEchAM4BAAAA.Lithari:BAAALgADCggJCAAAAA==.',
Lo='Lofwyr:BAACLgAFFH8FAAIgAAMJyQGETwCGAAAgAAMJyQGETwCGAAAuAAQKfzQAAiAACQmjEm0dAOoBACAACQmjEm0dAOoBAAAA.Lootadots:BAAALgAECgEJAQABLgAECgYJGAAIAF4UAA==.',
Lu='Lumes:BAAALgAECgUJBQAAAA==.Lumie:BAABLgAECn8mAAMMAAkJAyCgCADCAgAMAAkJAyCgCADCAgAbAAcJ4BGONABEAQABLgAFFAMJBwADAMwPAA==.Lumiea:BAAALgAECgYJBgABLgAFFAMJBwADAMwPAA==.Lunar:BAAALgADCgIJAgABLgAFFAYJEQAZAMwGAA==.Lunie:BAACLgAFFH8HAAIDAAMJzA9gQACqAAADAAMJzA9gQACqAAAuAAQKfx0AAgMACAnTHvYRALwCAAMACAnTHvYRALwCAAAA.',
Ma='Magadeoz:BAABLgAECn8UAAIBAAcJ6QqnsQAcAQABAAcJ6QqnsQAcAQAAAA==.Magicshow:BAACLgAFFH8GAAIBAAMJpQcXigDKAAABAAMJpQcXigDKAAAuAAQKfx0AAgEACAn1EPyUAKoBAAEACAn1EPyUAKoBAAAA.Malachite:BAAALgADCgQJBAABLgAFFAYJEQAZAMwGAA==.Malzahar:BAAALgADCgEJAgAAAA==.',
Mc='Mcdracula:BAAALgAECgcJEgAAAA==.',
Mi='Milfred:BAAALgAFFAEJAQAAAA==.Mistrniceguy:BAAALgAECgEJAQAAAA==.',
Mo='Moarticia:BAAALgAECgYJCwABLgAFFAIJBQAgAFkRAA==.Moonbelle:BAAALgAECgcJDAABLgAFFAYJEQAZAMwGAA==.',
Mu='Murthius:BAAALgAECgYJEgAAAA==.Musky:BAAALgAECgEJAgAAAA==.',
My='Myoushi:BAAALgADCgEJAQAAAA==.',
Na='Naâmah:BAAALgAECgUJBQAAAA==.',
Ne='Necromachine:BAACLgAFFH8LAAIEAAQJOQvQeQAOAQAEAAQJOQvQeQAOAQAuAAQKfxwAAwQACQmYF5p5AG0BAAQACQmYF5p5AG0BAA8AAglXBn8+AFYAAAAA.Neiry:BAAALgADCgcJBwAAAA==.Neon:BAAALgAECgYJCwABLgAECgkJNAAXACMlAA==.',
No='Noctislucis:BAACLgAFFH8FAAIUAAQJnAFqeQCEAAAUAAQJnAFqeQCEAAAuAAQKfyAABBgACQn+CsEZAMwAABQABwmkCQOaAOkAABgABwkGCsEZAMwAABYAAQlyAISDAAMAAAAA.Noj:BAAALgADCgUJBQAAAA==.Noobdk:BAABLgAFFH8GAAIPAAIJVCU6MwBnAAAPAAIJVCU6MwBnAAABLgAFFAYJGgACAPMiAA==.Noobmonkey:BAACLgAFFH8aAAICAAYJ8yKGBABLAgACAAYJ8yKGBABLAgAuAAQKfzMAAgIACQn4JRYBAGIDAAIACQn4JRYBAGIDAAAA.Noobwarr:BAAALgAECgYJBgABLgAFFAYJGgACAPMiAA==.Novax:BAAALgAECgQJBgAAAA==.',
Nu='Numeral:BAABLgAFFH8GAAMMAAIJtw32DQCOAAAMAAIJtw32DQCOAAAbAAIJsBFKLgCIAAAAAA==.',
Ol='Olegregg:BAAALgADCgUJCAAAAA==.',
On='Onzynn:BAAALgADCgcJCAAAAA==.',
Pa='Paracelsus:BAAALgAECgYJCwAAAA==.',
Pe='Pepka:BAAALgAECgYJCwAAAA==.',
Ph='Phillcollins:BAABLgAECn8lAAMGAAYJfhuUOQDEAQAGAAYJfhuUOQDEAQAXAAYJpxLQRQAYAQABLgAECgcJFwAgAEwUAA==.',
Pi='Pinktide:BAAALgAECgYJDAABLgAFFAgJIQAGAAQeAA==.',
Po='Pouka:BAAALgAECggJCAABLgAECgkJNAAOALslAA==.Power:BAAALgADCgcJBwAAAA==.',
Pr='Prettypoison:BAABLgAECn8yAAIaAAkJaxmVIwBRAgAaAAkJaxmVIwBRAgAAAA==.',
Pu='Putz:BAACLgAFFH8HAAIUAAMJVho7TgD7AAAUAAMJVho7TgD7AAAuAAQKf00AAxQACQlEJPoEADUDABQACQlEJPoEADUDABgAAQnqEbszADIAAAAA.',
Ra='Raditz:BAAALgADCgYJBgABLgAFFAgJIQAGAAQeAA==.Rainbow:BAABLgAECn8vAAIdAAkJWx+lCQD7AgAdAAkJWx+lCQD7AgABLgAECgkJNAAXACMlAA==.Rastasham:BAAALgAECggJDgAAAA==.Ratfondler:BAACLgAFFH8IAAMcAAMJah6LFwABAQAcAAMJah6LFwABAQAdAAEJcwZPZwApAAAuAAQKfywAAxwACQlMI48DACYDABwACQlMI48DACYDAB0ABAlSDwBtAMcAAAAA.',
Re='Reialaleigh:BAAALgAECgUJDQAAAA==.',
Ri='Ricanthetank:BAAALgAECgQJBAAAAA==.',
Ry='Rysho:BAAALgAECgEJAQAAAA==.',
Sa='Sabeam:BAACLgAFFH8VAAIUAAUJTBefCQCQAQAUAAUJTBefCQCQAQAuAAQKfzAAAhQACQnwH84HAE0DABQACQnwH84HAE0DAAAA.Saberdiva:BAABLgAECn8zAAIHAAgJlBEVjwBRAQAHAAgJlBEVjwBRAQAAAA==.Sabershot:BAAALgADCgMJAwAAAA==.Sabersidious:BAAALgADCgUJBQAAAA==.Saberthyr:BAAALgADCgkJEQAAAA==.Saberwookie:BAAALgADCgUJBQAAAA==.Sabs:BAAALgAFFAIJAgABLgAFFAUJFQAUAEwXAA==.Sagesteppe:BAAALgAECgYJEgAAAA==.Santhon:BAAALgAECgEJAwAAAA==.',
Sc='Scotticus:BAABLgAECn8jAAIEAAgJKg/BjwBDAQAEAAgJKg/BjwBDAQAAAA==.',
Se='Seditionist:BAABLgAECn8fAAIXAAgJIQUTVQDhAAAXAAgJIQUTVQDhAAAAAA==.Sellis:BAAALgADCgEJAQAAAA==.',
Sh='Shakira:BAAALgADCgkJCQABLgAECgUJDQAQAAAAAA==.Shammywow:BAAALgADCgEJAQAAAA==.Shamon:BAAALgAECgkJBQAAAA==.Shinju:BAAALgAECgEJAQAAAA==.Shåtheed:BAAALgADCgYJBgAAAA==.',
Si='Sidthekid:BAAALgAECgYJEgAAAA==.Sinayion:BAABLgAECn8lAAIVAAkJIwQPJgDhAAAVAAkJIwQPJgDhAAAAAA==.',
Sl='Sluggina:BAAALgAECgIJAwAAAA==.',
St='Stepbro:BAAALgAECgEJAQABLgAECggJGQAMAO4aAA==.Stepdemonh:BAAALgADCgkJEwAAAA==.Stepsis:BAAALgAFFAEJAQABLgAECggJGQAMAO4aAA==.Stinkoman:BAAALgAECgQJBwABLgAECgQJCAAQAAAAAA==.',
Su='Sunarena:BAABLgAECn8fAAIHAAkJJg8XiQBbAQAHAAkJJg8XiQBbAQAAAA==.',
Ta='Tankobell:BAABLgAECn8bAAIHAAkJBhHFWAC/AQAHAAkJBhHFWAC/AQAAAA==.Tavius:BAAALgADCgEJAQAAAA==.',
Te='Terrible:BAEALgAECgcJAgABLgAFFAcJHAAIAM8bAA==.',
Th='Thannatos:BAAALgAECgEJAQAAAA==.Thejuiciest:BAAALgADCgEJAgAAAA==.',
To='Tommet:BAAALgADCgUJBQAAAA==.Toukadh:BAAALgAECgYJAgAAAA==.',
Tr='Truart:BAAALgAECgQJCQAAAA==.',
Tu='Tuerjoie:BAABLgAECn8mAAIBAAgJQhiQUADnAQABAAgJQhiQUADnAQAAAA==.',
Tw='Twíla:BAAALgADCgYJCwAAAA==.',
Ty='Tywin:BAAALgAECgMJAwAAAA==.',
Ug='Ugooboom:BAAALgAECgEJAQAAAA==.',
Uh='Uh:BAAALgADCgYJDAAAAA==.',
Un='Unclemagic:BAAALgAECgYJCwABLgAFFAUJCgAOALIPAA==.',
Ut='Utopia:BAAALgAECgQJAwAAAA==.',
Va='Valesko:BAAALgAFFAEJAQAAAA==.Varfus:BAACLgAFFH8hAAIYAAgJ6x9WAACPAgAYAAgJ6x9WAACPAgAuAAQKfzMAAhgACQlKJnAAAFwDABgACQlKJnAAAFwDAAAA.',
Ve='Velentre:BAAALgAECgcJCQAAAA==.',
Vi='Vichy:BAAALgAECgYJCQAAAA==.Vikstyn:BAAALgAECgEJBAAAAA==.',
Vu='Vulquin:BAAALgAECgUJBQAAAA==.',
We='Weather:BAAALgAECgYJCAAAAA==.',
Wi='Wigskid:BAAALgADCgEJAQAAAA==.Winney:BAABLgAECn8lAAIHAAkJwSQKBgBAAwAHAAkJwSQKBgBAAwAAAA==.',
Wo='Wolfjob:BAAALgADCgUJBQAAAA==.Wouka:BAABLgAECn80AAQOAAkJuyXRAwBSAwAOAAkJqSXRAwBSAwAKAAYJqiPVAwBQAgANAAIJsiMGKwBnAAAAAA==.',
Wu='Wukong:BAAALgADCgMJAwAAAA==.',
Ya='Yarlyah:BAAALgADCgkJDgABLgAECgIJAgAQAAAAAA==.',
Yo='Yoyomba:BAAALgAECgUJBQABLgAECggJJQAcALgaAA==.',
Za='Zargonia:BAAALgAECgEJAQAAAA==.Zaria:BAAALgADCgUJBQAAAA==.',
Ze='Zendetra:BAAALgADCgUJBQABLgAECgQJDwAQAAAAAA==.Zeposo:BAABLgAECn8jAAMMAAgJuhwuDgCBAgAMAAgJuhwuDgCBAgAbAAEJyAQ3kgAlAAAAAA==.Zeppo:BAAALgAECgIJAwABLgAECggJIwAMALocAA==.Zeptide:BAABLgAECn9RAAMGAAkJLx37CwD4AgAGAAkJLx37CwD4AgAXAAgJ5xP3JwCqAQABLgAECggJIwAMALocAA==.Zervish:BAAALgAECgEJAQAAAA==.',
Zo='Zoli:BAAALgAECggJEQAAAA==.',
Zr='Zrichfu:BAAALgADCgIJAgABLgAFFAMJBQAOALoFAA==.',
Zu='Zugnuts:BAAALgAECgcJBwAAAA==.',
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
