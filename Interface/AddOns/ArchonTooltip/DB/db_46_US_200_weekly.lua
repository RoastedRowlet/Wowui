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

local lookup = {'Monk-Brewmaster','Druid-Restoration','DeathKnight-Unholy','Mage-Frost','Mage-Arcane','Shaman-Restoration','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Warlock-Affliction','Shaman-Enhancement','Priest-Holy','Warlock-Destruction','Warlock-Demonology','DeathKnight-Blood','Unknown-Unknown','Hunter-Survival','Hunter-Marksmanship','DemonHunter-Devourer','Paladin-Protection','DemonHunter-Havoc','Shaman-Elemental','DemonHunter-Vengeance','Priest-Discipline','DeathKnight-Frost','Hunter-BeastMastery','Priest-Shadow','Monk-Windwalker','Monk-Mistweaver','Paladin-Holy','Evoker-Augmentation',}
local provider = {region='US',realm='Smolderthorn',name='US',type='weekly',zone=46,date='2026-05-30',data={Ac='Achoo:BAAALgAECgcJEwAAAA==.Acorn:BAAALgADCgMJBAAAAA==.',
Ai='Aitnd:BAAALgADCggJDgAAAA==.Aitns:BAAALgADCgUJBQAAAA==.',
Ak='Akabara:BAAALgAECgMJAwAAAA==.',
Al='Alatyr:BAAALgAECgUJBQABLgAECgkJGQABAHEYAA==.Alduinn:BAAALgADCggJEAAAAA==.',
Am='Amilde:BAAALgAECgkJEQABLgAFFAMJCAACAGkSAA==.Amongor:BAABLgAECn8YAAIDAAYJ3h95UAAAAgADAAYJ3h95UAAAAgAAAA==.',
An='Anarisa:BAABLgAECn9JAAMEAAkJRRyDGgClAgAEAAkJRRyDGgClAgAFAAUJcRGGCwAeAQAAAA==.',
Aq='Aquatide:BAAALgAECgYJBgABLgAFFAcJIAAGAHAdAA==.',
Ar='Artoria:BAAALgADCgkJCwAAAA==.',
At='Athorama:BAAALgAECgUJCwAAAA==.Atra:BAAALgAECgEJAQAAAA==.',
Av='Avelise:BAABLgAECn8UAAIEAAcJkBelaQADAgAEAAcJkBelaQADAgABLgAFFAMJCAACAGkSAA==.Averse:BAACLgAFFH8SAAIDAAQJWx/TOABhAQADAAQJWx/TOABhAQAuAAQKfzUAAgMACQk0HqAUALkCAAMACQk0HqAUALkCAAAA.',
Az='Azazygos:BAAALgAECgMJAwAAAA==.',
Ba='Baeloth:BAAALgADCgcJDAAAAA==.Barkknight:BAEALgAECgkJBQABLgAFFAQJCwAHAO8PAA==.Barley:BAAALgAECgUJBQAAAA==.Bauce:BAAALgAECgYJBgAAAA==.',
Be='Bearretheon:BAAALgADCgEJAQAAAA==.Benchtally:BAAALgAECgYJDAAAAA==.Bepizo:BAACLgAFFH8GAAMIAAMJ6x1fMQDFAAAIAAIJhCFfMQDFAAAJAAEJuBb4MABRAAAuAAQKf0YAAwkACQndJNEIAEoCAAkABgnSItEIAEoCAAgABwmzItUpABICAAAA.',
Bl='Bluetide:BAACLgAFFH8gAAIGAAcJcB3cAwBbAgAGAAcJcB3cAwBbAgAuAAQKfykAAgYACQmOJkkAAOUDAAYACQmOJkkAAOUDAAAA.',
Br='Brokemav:BAABLgAECn8vAAIKAAcJESGWAgCTAgAKAAcJESGWAgCTAgAAAA==.Brooklin:BAABLgAECn8yAAIEAAkJnh7dKwDDAgAEAAkJnh7dKwDDAgAAAA==.',
Bu='Busky:BAABLgAECn8lAAMGAAkJAhVaKwDfAQAGAAkJAhVaKwDfAQALAAcJkhFUFABTAQAAAA==.',
Ca='Carboncredit:BAABLgAECn8iAAILAAkJrRAICgAyAgALAAkJrRAICgAyAgAAAA==.Cassiopea:BAABLgAECn8ZAAIMAAgJ7hqGFQARAgAMAAgJ7hqGFQARAgAAAA==.Caysia:BAABLgAFFH8IAAICAAMJaRIDNwDBAAACAAMJaRIDNwDBAAAAAA==.',
Ce='Cellcept:BAABLgAECn8UAAINAAUJ4R1ZDABbAQANAAUJ4R1ZDABbAQAAAA==.',
Ch='Chareth:BAABLgAECn8oAAIEAAkJNgpOaACTAQAEAAkJNgpOaACTAQAAAA==.Charlee:BAAALgADCgcJBwAAAA==.Chaunticleer:BAAALgAECgcJCwAAAA==.Chinchillada:BAABLgAECn8aAAIEAAYJxxPrkQA5AQAEAAYJxxPrkQA5AQAAAA==.',
Ci='Cinderfal:BAAALgAECgEJAgAAAA==.',
Co='Coldbrewed:BAAALgAECgYJBgAAAA==.Cowladin:BAAALgADCgYJBgABLgAECggJFwAOALYeAA==.',
Cr='Crossover:BAAALgADCgYJBgAAAA==.',
['Cà']='Càss:BAAALgAECgQJBQABLgAECggJGQAMAO4aAA==.',
Da='Dabajabaza:BAABLgAECn8wAAIPAAkJ0goYHwBCAQAPAAkJ0goYHwBCAQAAAA==.Dabergerak:BAACLgAFFH8JAAIIAAMJXCH6IwAJAQAIAAMJXCH6IwAJAQAuAAQKfysAAggACQmcJVgCAEIDAAgACQmcJVgCAEIDAAAA.Daenys:BAAALgAECgMJAwABLgAFFAgJLAAKAA0bAA==.Daggart:BAAALgAECgkJDgAAAA==.Dagrimreaper:BAAALgADCgcJBgABLgAECgUJCgAQAAAAAA==.Dakrus:BAACLgAFFH8FAAIRAAMJmg3WGwDgAAARAAMJmg3WGwDgAAAuAAQKfyUAAxIACQkwGVIgACMCABIACAmpFlIgACMCABEABgk9DqgoAEoBAAAA.Darthßsaber:BAAALgADCgUJBQAAAA==.Dawin:BAAALgAECggJDQAAAA==.Dax:BAAALgADCgYJBgAAAA==.',
De='Deadazz:BAAALgAFFAEJAQABLgAFFAUJCgAOALIPAA==.Deadputz:BAAALgAECggJEwABLgAFFAMJBwATAFYaAA==.Deeiinndu:BAAALgAECgYJEAAAAA==.Dejanira:BAABLgAECn8gAAICAAkJzhG1OwCTAQACAAkJzhG1OwCTAQAAAA==.Demonslayerr:BAAALgADCgQJBAAAAA==.Demotope:BAAALgADCgcJDAABLgAECgYJDAAQAAAAAA==.',
Di='Diddily:BAABLgAECn8VAAMUAAgJWxUTHwAQAQAUAAgJWxUTHwAQAQAHAAIJ7QP9lAEkAAAAAA==.Diesverdi:BAAALgAECgMJAwAAAA==.Dirtylilskin:BAAALgADCgkJHQAAAA==.',
Do='Dookie:BAAALgAECgQJBAAAAA==.',
Dr='Draconae:BAABLgAECn8bAAIVAAYJWQc7NgC/AAAVAAYJWQc7NgC/AAAAAA==.Dracotope:BAAALgAECgYJDAAAAA==.Dragonjoy:BAABLgAECn8kAAIPAAkJORafEwC9AQAPAAkJORafEwC9AQAAAA==.Drathier:BAAALgAECgIJAgAAAA==.Dridarok:BAABLgAECn8gAAIIAAkJqQy9KACiAQAIAAkJqQy9KACiAQAAAA==.',
Ei='Eighttyhd:BAAALgADCgQJBAAAAA==.Eightyhd:BAAALgADCgIJAgAAAA==.Eirny:BAAALgAECgMJBAAAAA==.',
El='Element:BAAALgADCgEJAQABLgAFFAMJBgAIAOsdAA==.Elise:BAABLgAECn8kAAMNAAkJQhckCQAvAgANAAgJzBckCQAvAgAKAAgJARH4DgBBAQAAAA==.Elstrid:BAABLgAECn8XAAIOAAgJth43PAAcAgAOAAgJth43PAAcAgAAAA==.',
Er='Erzaflame:BAAALgADCgEJAQAAAA==.',
Eu='Euphoria:BAAALgAECgMJAwABLgAECgkJNAAWACMlAA==.',
Ev='Evochre:BAAALgAECgUJCQAAAA==.',
Fa='Faerine:BAAALgADCgcJBwAAAA==.Fantasy:BAABLgAECn80AAIWAAkJIyWCAgBDAwAWAAkJIyWCAgBDAwAAAA==.',
Fe='Felbourn:BAACLgAFFH8FAAIVAAIJHB1hGACfAAAVAAIJHB1hGACfAAAuAAQKfyAABBUACQlkIY4IANkCABUACAmJIY4IANkCABcAAgktFikeAI8AABMAAgm7CW/MAF0AAAAA.Fendraim:BAAALgAECgQJBgABLgAECgcJEQAQAAAAAA==.',
Fi='Figurefour:BAAALgAECgkJDwAAAA==.',
Fo='Foedris:BAAALgADCgUJBQAAAA==.Foxfire:BAAALgAECgQJCAAAAA==.',
Fr='Frailboosy:BAACLgAFFH8KAAIHAAMJshePUgDnAAAHAAMJshePUgDnAAAuAAQKf1sAAgcACQkYIlkJAAoDAAcACQkYIlkJAAoDAAAA.Fri:BAAALgADCgkJCQAAAA==.Frigamortis:BAAALgAECgYJCwAAAA==.',
Ge='Gemini:BAAALgAECgQJBAAAAA==.',
Gi='Gilferno:BAAALgAECgQJBAAAAA==.',
Gl='Glitz:BAABLgAFFH8FAAIEAAUJawQbZwD3AAAEAAUJawQbZwD3AAABLgAFFAYJEQAYAMwGAA==.',
Gn='Gnarfok:BAAALgAECgQJDwAAAA==.',
Go='Goopster:BAAALgADCgcJCQABLgAECgQJBgAQAAAAAA==.',
Gr='Graamps:BAAALgAECgUJCAAAAA==.Gravedigger:BAACLgAFFH8JAAMPAAMJNxrLGwDfAAAPAAMJNxrLGwDfAAAZAAEJZACeIgAqAAAuAAQKfzQAAg8ACQncH0cIAH8CAA8ACQncH0cIAH8CAAAA.',
Gu='Gunde:BAAALgAECgkJBAAAAA==.Gust:BAAALgAECgQJDwAAAA==.',
Ha='Hatredx:BAAALgADCgIJAgAAAA==.',
He='Heisenberg:BAAALgAECgQJCAABLgAFFAMJCAAaAJYUAA==.',
Ho='Holywagyu:BAAALgAECgYJBgAAAA==.',
Hy='Hyõrinmaru:BAAALgAECgMJAwAAAA==.',
Ih='Iheal:BAAALgAECgEJAQAAAA==.',
In='Inarios:BAABLgAECn8oAAQYAAgJ/h2WCwCYAgAYAAgJ/h2WCwCYAgAbAAMJphVERgDPAAAMAAEJtwyIagAqAAAAAA==.Inshape:BAAALgAECgYJEwAAAA==.',
Ir='Ironnman:BAAALgAECgEJAQABLgAECgkJGQABAHEYAA==.Ironnmonk:BAABLgAECn8ZAAQBAAkJcRiBGwAnAgABAAkJcRiBGwAnAgAcAAEJihG1igAzAAAdAAEJUgQwdQAcAAAAAA==.',
Ja='Javlin:BAAALgAECgEJAgAAAA==.',
Jo='Joltarin:BAAALgAECgEJAQABLgAECggJFwAOALYeAA==.',
Ju='Jujufya:BAAALgAECgIJAgABLgAECgcJEAAQAAAAAA==.Jujukni:BAAALgAECgUJCAABLgAECgcJEAAQAAAAAA==.Jujumon:BAAALgAECgcJEAAAAA==.Jujuzul:BAAALgADCgUJBgABLgAECgcJEAAQAAAAAA==.Justimp:BAACLgAFFH8GAAIOAAMJTQiWdADAAAAOAAMJTQiWdADAAAAuAAQKfyQAAg4ACQl4FKk7AN8BAA4ACQl4FKk7AN8BAAAA.',
Ka='Kanon:BAAALgAECgYJDQAAAA==.Kanook:BAAALgAECgMJAwAAAA==.Karlek:BAABLgAFFH8GAAMeAAMJ2gQzMACbAAAeAAMJ2gQzMACbAAAHAAEJ6AESqQA1AAAAAA==.',
Ki='Kikily:BAAALgADCgkJCQAAAA==.',
Ko='Konsistency:BAABLgAECn8fAAITAAcJlA6icgBNAQATAAcJlA6icgBNAQAAAA==.Konviction:BAABLgAECn8fAAMHAAkJ/RF6egBeAQAHAAkJ/RF6egBeAQAUAAIJZwKzUAAcAAAAAA==.',
Kr='Kreel:BAAALgADCggJCAAAAA==.Krogg:BAAALgADCgcJBwAAAA==.',
La='Lalana:BAABLgAECn8bAAIaAAYJzwvQlAD7AAAaAAYJzwvQlAD7AAAAAA==.Lan:BAAALgAECgcJBwAAAA==.Landin:BAAALgAECgcJBwAAAA==.',
Li='Liari:BAEBLgAECn8cAAIEAAgJKwoZiwBGAQAEAAgJKwoZiwBGAQABLgAFFAQJCwAHAO8PAA==.Libra:BAAALgADCgEJAQAAAA==.Lilith:BAACLgAFFH8RAAMYAAYJzAbHCABRAQAYAAYJzAbHCABRAQAbAAQJcwk7IQDEAAAuAAQKfyEAAxgACQmpGG4SACECABgACAk0GW4SACECABsABwmVHEchAM4BAAAA.Lithari:BAAALgADCggJCAAAAA==.',
Lo='Lofwyr:BAACLgAFFH8FAAIfAAMJyQGkQwCQAAAfAAMJyQGkQwCQAAAuAAQKfysAAh8ACQn7EP8dAM4BAB8ACQn7EP8dAM4BAAAA.Lootadots:BAAALgAECgEJAQABLgAECgYJGAAIAF4UAA==.',
Lu='Lumie:BAABLgAECn8mAAMMAAkJAyCgCADCAgAMAAkJAyCgCADCAgAbAAcJ4BEkLwBCAQAAAA==.Lumiea:BAAALgAECgYJBgABLgAECgkJJgAMAAMgAA==.Lunar:BAAALgADCgIJAgABLgAFFAYJEQAYAMwGAA==.Lunie:BAABLgAECn8dAAICAAgJ0x5KEAC+AgACAAgJ0x5KEAC+AgABLgAECgkJJgAMAAMgAA==.',
Ma='Magadeoz:BAAALgAECgcJEwAAAA==.Magicshow:BAACLgAFFH8GAAIEAAMJpQcTegDNAAAEAAMJpQcTegDNAAAuAAQKfx0AAgQACAn1EPyUAKoBAAQACAn1EPyUAKoBAAAA.Malachite:BAAALgADCgQJBAABLgAFFAYJEQAYAMwGAA==.Malzahar:BAAALgADCgEJAgAAAA==.',
Mc='Mcdracula:BAAALgAECgcJDQAAAA==.',
Mi='Milfred:BAAALgADCggJCAAAAA==.Mistrniceguy:BAAALgAECgEJAQAAAA==.',
Mo='Moarticia:BAAALgAECgYJCwABLgAFFAIJBQAfAFkRAA==.Moonbelle:BAAALgAECgcJDAABLgAFFAYJEQAYAMwGAA==.',
Mu='Murthius:BAAALgAECgYJCwAAAA==.Musky:BAAALgAECgEJAgAAAA==.',
My='Myoushi:BAAALgADCgEJAQAAAA==.',
Na='Naâmah:BAAALgAECgUJBQAAAA==.',
Ne='Necromachine:BAACLgAFFH8HAAIDAAMJ2AqsjwDMAAADAAMJ2AqsjwDMAAAuAAQKfxsAAwMACQmYFx9vAHIBAAMACQmYFx9vAHIBAA8AAglXBn8+AFYAAAAA.Neiry:BAAALgADCgcJBwAAAA==.Neon:BAAALgAECgUJBQABLgAECgkJNAAWACMlAA==.',
No='Noctislucis:BAABLgAECn8gAAQXAAkJ/gr3FgDRAAATAAcJpAnZjQDmAAAXAAcJBgr3FgDRAAAVAAEJcgBocwACAAAAAA==.Noj:BAAALgADCgUJBQAAAA==.Noobdk:BAABLgAFFH8GAAIPAAIJVCXGKgBpAAAPAAIJVCXGKgBpAAABLgAFFAYJGgABAPMiAA==.Noobmonkey:BAACLgAFFH8aAAIBAAYJ8yKJAgBZAgABAAYJ8yKJAgBZAgAuAAQKfzMAAgEACQn4Jd0AAGYDAAEACQn4Jd0AAGYDAAAA.Noobwarr:BAAALgAECgYJBgABLgAFFAYJGgABAPMiAA==.Novax:BAAALgAECgMJAwAAAA==.',
Nu='Numeral:BAABLgAFFH8GAAMbAAIJsBE0JwCQAAAbAAIJsBE0JwCQAAAMAAIJtw32DQCOAAAAAA==.',
Ol='Olegregg:BAAALgADCgUJCAAAAA==.',
On='Onzynn:BAAALgADCgcJCAAAAA==.',
Pa='Paracelsus:BAAALgAECgYJCwAAAA==.',
Pe='Pepka:BAAALgAECgYJCwAAAA==.',
Ph='Phillcollins:BAABLgAECn8dAAMGAAYJfht7MwDJAQAGAAYJfht7MwDJAQAWAAEJhgw4lAAwAAABLgAECgcJFwAfAEwUAA==.',
Pi='Pinktide:BAAALgAECgYJDAABLgAFFAcJIAAGAHAdAA==.',
Po='Pouka:BAAALgAECggJCAABLgAECgkJNAAOALslAA==.Power:BAAALgADCgcJBwAAAA==.',
Pr='Prettypoison:BAABLgAECn8oAAIaAAcJPRlTSACxAQAaAAcJPRlTSACxAQAAAA==.',
Pu='Putz:BAACLgAFFH8HAAITAAMJVhrkQgAFAQATAAMJVhrkQgAFAQAuAAQKfz8AAxMACQn+IqAJAO0CABMACQn+IqAJAO0CABcAAQnqEbAuADIAAAAA.',
Ra='Raditz:BAAALgADCgYJBgABLgAFFAcJIAAGAHAdAA==.Rainbow:BAABLgAECn8rAAIdAAkJHB2ZCwDAAgAdAAkJHB2ZCwDAAgABLgAECgkJNAAWACMlAA==.Rastasham:BAAALgAECggJDgAAAA==.Ratfondler:BAACLgAFFH8IAAMcAAMJah4KFAANAQAcAAMJah4KFAANAQAdAAEJcwbPUAAvAAAuAAQKfywAAxwACQlMI9MCAC8DABwACQlMI9MCAC8DAB0ABAlSD4NeAMMAAAAA.',
Re='Reialaleigh:BAAALgAECgUJCAAAAA==.',
Ri='Ricanthetank:BAAALgAECgQJBAAAAA==.',
Ry='Rysho:BAAALgAECgEJAQAAAA==.',
Sa='Sabeam:BAACLgAFFH8VAAITAAUJTBefCQCQAQATAAUJTBefCQCQAQAuAAQKfzAAAhMACQnwH84HAE0DABMACQnwH84HAE0DAAAA.Saberdiva:BAABLgAECn8sAAIHAAgJYxH6hQBIAQAHAAgJYxH6hQBIAQAAAA==.Sabersidious:BAAALgADCgUJBQAAAA==.Saberthyr:BAAALgADCgkJEQAAAA==.Saberwookie:BAAALgADCgUJBQAAAA==.Sabs:BAAALgAFFAIJAgABLgAFFAUJFQATAEwXAA==.Sagesteppe:BAAALgAECgUJCwAAAA==.Santhon:BAAALgAECgEJAwAAAA==.',
Sc='Scotticus:BAABLgAECn8jAAIDAAgJKg+LggBJAQADAAgJKg+LggBJAQAAAA==.',
Se='Seditionist:BAABLgAECn8cAAIWAAYJ+gQBYACoAAAWAAYJ+gQBYACoAAAAAA==.Sellis:BAAALgADCgEJAQAAAA==.',
Sh='Shakira:BAAALgADCgkJCQABLgAECgUJCAAQAAAAAA==.Shammywow:BAAALgADCgEJAQAAAA==.Shamon:BAAALgAECgkJBQAAAA==.Shinju:BAAALgAECgEJAQAAAA==.Shåtheed:BAAALgADCgYJBgAAAA==.',
Si='Sidthekid:BAAALgAECgQJBQAAAA==.Sinayion:BAABLgAECn8gAAIUAAcJqQSLKwCnAAAUAAcJqQSLKwCnAAAAAA==.',
Sl='Sluggina:BAAALgAECgIJAwAAAA==.',
St='Stepdemonh:BAAALgADCgkJEwAAAA==.Stepsis:BAAALgAECgEJAQABLgAECggJGQAMAO4aAA==.Stinkoman:BAAALgAECgQJBwABLgAECgQJCAAQAAAAAA==.',
Su='Sunarena:BAABLgAECn8fAAIHAAkJJg/DfQBYAQAHAAkJJg/DfQBYAQAAAA==.',
Ta='Tankobell:BAABLgAECn8bAAIHAAkJBhGGTgDEAQAHAAkJBhGGTgDEAQAAAA==.Tavius:BAAALgADCgEJAQAAAA==.',
Te='Terrible:BAEALgAECgcJAgABLgAFFAYJGgAIAIEeAA==.',
Th='Thannatos:BAAALgAECgEJAQAAAA==.Thejuiciest:BAAALgADCgEJAgAAAA==.',
To='Tommet:BAAALgADCgUJBQAAAA==.Toukadh:BAAALgAECgYJAgAAAA==.',
Tr='Truart:BAAALgAECgQJCQAAAA==.',
Tu='Tuerjoie:BAABLgAECn8mAAIEAAgJQhicSADqAQAEAAgJQhicSADqAQAAAA==.',
Tw='Twíla:BAAALgADCgYJCwAAAA==.',
Ty='Tywin:BAAALgAECgMJAwAAAA==.',
Ug='Ugooboom:BAAALgAECgEJAQAAAA==.',
Uh='Uh:BAAALgADCgYJDAAAAA==.',
Ut='Utopia:BAAALgAECgQJAwAAAA==.',
Va='Valesko:BAAALgAECggJEAAAAA==.Varfus:BAACLgAFFH8gAAIXAAcJwSJNAABeAgAXAAcJwSJNAABeAgAuAAQKfzMAAhcACQlKJkgAAGQDABcACQlKJkgAAGQDAAAA.',
Ve='Velentre:BAAALgAECgYJCAAAAA==.',
Vi='Vichy:BAAALgAECgYJCQAAAA==.Vikstyn:BAAALgAECgEJBAAAAA==.',
Vu='Vulquin:BAAALgAECgUJBQAAAA==.',
We='Weather:BAAALgAECgYJCAAAAA==.',
Wi='Wigskid:BAAALgADCgEJAQAAAA==.Winney:BAABLgAECn8gAAIHAAgJCiTAEwC4AgAHAAgJCiTAEwC4AgAAAA==.',
Wo='Wolfjob:BAAALgADCgUJBQAAAA==.Wouka:BAABLgAECn80AAQOAAkJuyUGAwBcAwAOAAkJqSUGAwBcAwAKAAYJqiPVAwBQAgANAAIJsiPOJgBpAAAAAA==.',
Wu='Wukong:BAAALgADCgMJAwAAAA==.',
Ya='Yarlyah:BAAALgADCgkJDgAAAA==.',
Yo='Yoyomba:BAAALgAECgUJBQABLgAECggJJQAcALgaAA==.',
Za='Zargonia:BAAALgAECgEJAQAAAA==.Zaria:BAAALgADCgUJBQAAAA==.',
Ze='Zendetra:BAAALgADCgUJBQABLgAECgQJBwAQAAAAAA==.Zeposo:BAABLgAECn8cAAMMAAcJahfUIgCWAQAMAAcJahfUIgCWAQAbAAEJyAT2ggAmAAABLgAECgkJSgAGAC8dAA==.Zeppo:BAAALgAECgIJAwABLgAECgkJSgAGAC8dAA==.Zeptide:BAABLgAECn9KAAMGAAkJLx1nCgD5AgAGAAkJLx1nCgD5AgAWAAgJ5xNpIwCyAQAAAA==.Zervish:BAAALgAECgEJAQAAAA==.',
Zo='Zoli:BAAALgAECggJEQAAAA==.',
Zr='Zrichfu:BAAALgADCgIJAgABLgAFFAMJBQAOALoFAA==.',
Zu='Zugnuts:BAAALgADCgcJHAAAAA==.',
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
