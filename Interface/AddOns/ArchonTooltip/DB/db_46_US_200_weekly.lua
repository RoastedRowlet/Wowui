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

local lookup = {'Druid-Restoration','DeathKnight-Unholy','Mage-Frost','Mage-Arcane','Shaman-Restoration','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Warlock-Affliction','Shaman-Enhancement','Priest-Holy','Warlock-Demonology','DeathKnight-Blood','Hunter-Survival','Hunter-Marksmanship','DemonHunter-Devourer','Unknown-Unknown','Paladin-Protection','DemonHunter-Havoc','Warlock-Destruction','Shaman-Elemental','Priest-Discipline','DeathKnight-Frost','Hunter-BeastMastery','Priest-Shadow','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Paladin-Holy','Evoker-Augmentation','DemonHunter-Vengeance',}
local provider = {region='US',realm='Smolderthorn',name='US',type='weekly',zone=46,date='2026-05-23',data={Ac='Achoo:BAAALgAECgYJDAAAAA==.Acorn:BAAALgADCgMJBAAAAA==.',
Ai='Aitnd:BAAALgADCggJDgAAAA==.Aitns:BAAALgADCgUJBQAAAA==.',
Ak='Akabara:BAAALgAECgMJAwAAAA==.',
Al='Alduinn:BAAALgADCggJEAAAAA==.',
Am='Amilde:BAAALgAECgkJEQABLgAFFAMJBQABADAOAA==.Amongor:BAABLgAECn8YAAICAAYJ3h95UAAAAgACAAYJ3h95UAAAAgAAAA==.',
An='Anarisa:BAABLgAECn86AAMDAAkJvRl+JABuAgADAAkJvRl+JABuAgAEAAUJcRGGCwAeAQAAAA==.',
Aq='Aquatide:BAAALgAECgYJBgABLgAFFAYJHgAFAEEeAA==.',
Ar='Artoria:BAAALgADCgkJCwAAAA==.',
At='Athorama:BAAALgAECgQJBwAAAA==.Atra:BAAALgAECgEJAQAAAA==.',
Av='Avelise:BAABLgAECn8UAAIDAAcJkBelaQADAgADAAcJkBelaQADAgABLgAFFAMJBQABADAOAA==.Averse:BAACLgAFFH8OAAICAAQJJRpXPgBHAQACAAQJJRpXPgBHAQAuAAQKfzQAAgIACQkkHbQVAKQCAAIACQkkHbQVAKQCAAAA.',
Az='Azazygos:BAAALgAECgMJAwAAAA==.',
Ba='Baeloth:BAAALgADCgcJDAAAAA==.Barkknight:BAEALgAECgkJBQABLgAFFAMJBwAGALsQAA==.Barley:BAAALgAECgEJAQAAAA==.Bauce:BAAALgAECgYJBgAAAA==.',
Be='Bearretheon:BAAALgADCgEJAQAAAA==.Benchtally:BAAALgAECgYJDAAAAA==.Bepizo:BAABLgAECn9GAAMHAAkJ3STLBwBRAgAHAAYJ0iLLBwBRAgAIAAcJsyLVKQASAgAAAA==.',
Bl='Bluetide:BAACLgAFFH8eAAIFAAYJQR4gBgARAgAFAAYJQR4gBgARAgAuAAQKfykAAgUACQmOJjUAAOgDAAUACQmOJjUAAOgDAAAA.',
Br='Brokemav:BAABLgAECn8vAAIJAAcJESGWAgCTAgAJAAcJESGWAgCTAgAAAA==.Brooklin:BAABLgAECn8yAAIDAAkJnh7dKwDDAgADAAkJnh7dKwDDAgAAAA==.',
Bu='Busky:BAABLgAECn8lAAMFAAkJAhVaKwDfAQAFAAkJAhVaKwDfAQAKAAcJkhEhEgBTAQAAAA==.',
Ca='Carboncredit:BAABLgAECn8iAAIKAAkJrRAICgAyAgAKAAkJrRAICgAyAgAAAA==.Cassiopea:BAABLgAECn8ZAAILAAgJ7hpuEwAYAgALAAgJ7hpuEwAYAgAAAA==.Caysia:BAABLgAFFH8FAAIBAAMJMA43MwDEAAABAAMJMA43MwDEAAAAAA==.',
Ce='Cellcept:BAAALgAECgUJDgAAAA==.',
Ch='Chareth:BAABLgAECn8oAAIDAAkJNgqeXACsAQADAAkJNgqeXACsAQAAAA==.Charlee:BAAALgADCgcJBwAAAA==.Chaunticleer:BAAALgAECgcJCwAAAA==.Chinchillada:BAABLgAECn8WAAIDAAUJVRSTrAAMAQADAAUJVRSTrAAMAQAAAA==.',
Co='Coldbrewed:BAAALgAECgYJBgAAAA==.Cowladin:BAAALgADCgYJBgABLgAECggJFwAMALYeAA==.',
Cr='Crossover:BAAALgADCgYJBgAAAA==.',
['Cà']='Càss:BAAALgAECgQJBQABLgAECggJGQALAO4aAA==.',
Da='Dabajabaza:BAABLgAECn8rAAINAAgJ3guGIQAXAQANAAgJ3guGIQAXAQAAAA==.Dabergerak:BAACLgAFFH8GAAIIAAMJXCECIQAAAQAIAAMJXCECIQAAAQAuAAQKfysAAggACQmcJccBAEsDAAgACQmcJccBAEsDAAAA.Daenys:BAAALgAECgMJAwABLgAFFAgJLAAJAA0bAA==.Daggart:BAAALgAECgkJCwAAAA==.Dagrimreaper:BAAALgADCgcJBAAAAA==.Dakrus:BAACLgAFFH8FAAIOAAMJmg2cGADkAAAOAAMJmg2cGADkAAAuAAQKfyUAAw8ACQkwGVIgACMCAA8ACAmpFlIgACMCAA4ABgk9DvwlAEwBAAAA.Darthßsaber:BAAALgADCgUJBQAAAA==.Dawin:BAAALgAECgYJBwAAAA==.Dax:BAAALgADCgYJBgAAAA==.',
De='Deadazz:BAAALgAECgYJEwABLgAFFAUJCQAMAMAMAA==.Deadputz:BAAALgAECggJDQABLgAECgkJPwAQAP4iAA==.Deeiinndu:BAAALgAECgYJDAAAAA==.Dejanira:BAABLgAECn8gAAIBAAkJzhElOACUAQABAAkJzhElOACUAQAAAA==.Demonslayerr:BAAALgADCgQJBAAAAA==.Demotope:BAAALgADCgcJDAABLgAECgYJDAARAAAAAA==.',
Di='Diddily:BAABLgAECn8VAAMSAAgJWxUTHwAQAQASAAgJWxUTHwAQAQAGAAIJ7QMsegEmAAAAAA==.Diesverdi:BAAALgAECgMJAwAAAA==.Dirtylilskin:BAAALgADCgkJHQAAAA==.',
Do='Dookie:BAAALgAECgQJBAAAAA==.',
Dr='Draconae:BAABLgAECn8YAAITAAYJVwduMQDDAAATAAYJVwduMQDDAAAAAA==.Dracotope:BAAALgAECgYJDAAAAA==.Dragonjoy:BAABLgAECn8kAAINAAkJORapEQDCAQANAAkJORapEQDCAQAAAA==.Drathier:BAAALgAECgIJAgAAAA==.Dridarok:BAABLgAECn8gAAIIAAkJqQzJJACqAQAIAAkJqQzJJACqAQAAAA==.',
Ei='Eighttyhd:BAAALgADCgQJBAAAAA==.Eightyhd:BAAALgADCgIJAgAAAA==.Eirny:BAAALgAECgMJBAAAAA==.',
El='Element:BAAALgADCgEJAQABLgAECgkJRgAHAN0kAA==.Elise:BAABLgAECn8kAAMUAAkJQhckCQAvAgAUAAgJzBckCQAvAgAJAAgJARH4DgBBAQAAAA==.Elstrid:BAABLgAECn8XAAIMAAgJth43PAAcAgAMAAgJth43PAAcAgAAAA==.',
Er='Erzaflame:BAAALgADCgEJAQAAAA==.',
Eu='Euphoria:BAAALgAECgMJAwABLgAECgkJMwAVACMlAA==.',
Ev='Evochre:BAAALgAECgUJCQAAAA==.',
Fa='Faerine:BAAALgADCgcJBwAAAA==.Fantasy:BAABLgAECn8zAAIVAAkJIyUWAgBFAwAVAAkJIyUWAgBFAwAAAA==.',
Fe='Felbourn:BAACLgAFFH8FAAITAAIJHB1WFACtAAATAAIJHB1WFACtAAAuAAQKfx4AAxMACAmJIY4IANkCABMACAmJIY4IANkCABAAAgm7CW/MAF0AAAAA.Fendraim:BAAALgAECgQJBAABLgAECgcJEQARAAAAAA==.',
Fi='Figurefour:BAAALgAECgkJDwAAAA==.',
Fo='Foedris:BAAALgADCgUJBQAAAA==.Foxfire:BAAALgAECgQJCAAAAA==.',
Fr='Frailboosy:BAACLgAFFH8HAAIGAAMJ8BUkRwD0AAAGAAMJ8BUkRwD0AAAuAAQKf00AAgYACQmLIYIKAPgCAAYACQmLIYIKAPgCAAAA.Fri:BAAALgADCgkJCQAAAA==.Frigamortis:BAAALgAECgQJBgAAAA==.',
Ge='Gemini:BAAALgAECgQJBAAAAA==.',
Gi='Gilferno:BAAALgAECgQJBAAAAA==.',
Gl='Glitz:BAABLgAFFH8FAAIDAAUJawTRXAAAAQADAAUJawTRXAAAAQABLgAFFAYJEQAWAMwGAA==.',
Gn='Gnarfok:BAAALgAECgQJDgAAAA==.',
Go='Goopster:BAAALgADCgcJCQABLgAECgQJBgARAAAAAA==.',
Gr='Graamps:BAAALgAECgUJCAAAAA==.Gravedigger:BAACLgAFFH8GAAMNAAIJQBniIQCUAAANAAIJQBniIQCUAAAXAAEJZAATHAAuAAAuAAQKfzMAAg0ACQncHxcHAIgCAA0ACQncHxcHAIgCAAAA.',
Gu='Gunde:BAAALgAECgkJAQAAAA==.Gust:BAAALgAECgQJDwAAAA==.',
Ha='Hatredx:BAAALgADCgIJAgAAAA==.',
He='Heisenberg:BAAALgAECgQJCAABLgAFFAMJBwAYAJYUAA==.',
Ho='Holywagyu:BAAALgAECgYJBgAAAA==.',
Hy='Hyõrinmaru:BAAALgAECgMJAwAAAA==.',
Ih='Iheal:BAAALgAECgEJAQAAAA==.',
In='Inarios:BAABLgAECn8oAAQWAAgJ/h1FCgCiAgAWAAgJ/h1FCgCiAgAZAAMJphWvRADRAAALAAEJtwzXZAAqAAAAAA==.Inshape:BAAALgAECgYJEwAAAA==.',
Ir='Ironnman:BAAALgAECgEJAQABLgAECgkJGQAaAHEYAA==.Ironnmonk:BAABLgAECn8ZAAQaAAkJcRiBGwAnAgAaAAkJcRiBGwAnAgAbAAEJihH5fQA1AAAcAAEJUgQwdQAcAAAAAA==.',
Ja='Javlin:BAAALgAECgEJAgAAAA==.',
Jo='Joltarin:BAAALgAECgEJAQABLgAECggJFwAMALYeAA==.',
Ju='Jujufya:BAAALgADCgYJBgABLgAECgcJEAARAAAAAA==.Jujukni:BAAALgAECgUJBQABLgAECgcJEAARAAAAAA==.Jujumon:BAAALgAECgcJEAAAAA==.Jujuzul:BAAALgADCgUJBgABLgAECgcJEAARAAAAAA==.Justimp:BAABLgAECn8kAAIMAAkJeBR4NgDnAQAMAAkJeBR4NgDnAQAAAA==.',
Ka='Kanon:BAAALgAECgYJDAAAAA==.Kanook:BAAALgAECgMJAwAAAA==.Karlek:BAABLgAFFH8FAAIdAAMJ2gR/KwCiAAAdAAMJ2gR/KwCiAAAAAA==.',
Ki='Kikily:BAAALgADCgkJCQAAAA==.',
Ko='Konsistency:BAABLgAECn8fAAIQAAcJlA6icgBNAQAQAAcJlA6icgBNAQAAAA==.Konviction:BAABLgAECn8fAAMGAAkJ/RG6bAB1AQAGAAkJ/RG6bAB1AQASAAIJZwKlSgAcAAAAAA==.',
Kr='Kreel:BAAALgADCggJCAAAAA==.Krogg:BAAALgADCgcJBwAAAA==.',
La='Lalana:BAABLgAECn8XAAIYAAUJ0wzSmwDSAAAYAAUJ0wzSmwDSAAAAAA==.Lan:BAAALgAECgcJBwAAAA==.Landin:BAAALgAECgcJBwAAAA==.',
Li='Liari:BAEBLgAECn8cAAIDAAgJKwpxegBmAQADAAgJKwpxegBmAQABLgAFFAMJBwAGALsQAA==.Libra:BAAALgADCgEJAQAAAA==.Lilith:BAACLgAFFH8RAAMWAAYJzAbHCABRAQAWAAYJzAbHCABRAQAZAAQJcwkpHQDWAAAuAAQKfyEAAxYACQmpGG4SACECABYACAk0GW4SACECABkABwmVHEchAM4BAAAA.Lithari:BAAALgADCggJCAAAAA==.',
Lo='Lofwyr:BAACLgAFFH8FAAIeAAMJyQHWOwCYAAAeAAMJyQHWOwCYAAAuAAQKfyoAAh4ACQm9ELQcANABAB4ACQm9ELQcANABAAAA.Lootadots:BAAALgAECgEJAQABLgAECgYJGAAIAF4UAA==.',
Lu='Lumie:BAABLgAECn8mAAMLAAkJAyCgCADCAgALAAkJAyCgCADCAgAZAAcJ4BGbKgBVAQABLgAECggJHAABALgeAA==.Lumiea:BAAALgAECgEJAQABLgAECggJHAABALgeAA==.Lunie:BAABLgAECn8cAAIBAAgJuB64EQChAgABAAgJuB64EQChAgAAAA==.',
Ma='Magadeoz:BAAALgAECgcJEQAAAA==.Magicshow:BAABLgAECn8dAAIDAAgJ9RD8lACqAQADAAgJ9RD8lACqAQAAAA==.Malachite:BAAALgADCgQJBAABLgAFFAYJEQAWAMwGAA==.Malzahar:BAAALgADCgEJAgAAAA==.',
Mc='Mcdracula:BAAALgAECgcJDQAAAA==.',
Mi='Milfred:BAAALgADCggJCAAAAA==.Mistrniceguy:BAAALgAECgEJAQAAAA==.',
Mo='Moarticia:BAAALgAECgYJCwABLgAFFAIJBAARAAAAAA==.Moonbelle:BAAALgAECgcJDAABLgAFFAYJEQAWAMwGAA==.',
Mu='Murthius:BAAALgAECgEJAgAAAA==.Musky:BAAALgAECgEJAgAAAA==.',
My='Myoushi:BAAALgADCgEJAQAAAA==.',
Na='Naâmah:BAAALgAECgUJBQAAAA==.',
Ne='Necromachine:BAACLgAFFH8GAAICAAMJfwfmggDOAAACAAMJfwfmggDOAAAuAAQKfxsAAwIACQmYF7dnAHIBAAIACQmYF7dnAHIBAA0AAglXBn8+AFYAAAAA.Neiry:BAAALgADCgcJBwAAAA==.',
No='Noctislucis:BAABLgAECn8cAAQQAAkJqQrngQDzAAAQAAcJpAnngQDzAAAfAAcJEAkqGQDRAAATAAEJcgB0aAACAAAAAA==.Noj:BAAALgADCgUJBQAAAA==.Noobdk:BAABLgAFFH8FAAINAAIJVCVTJgBsAAANAAIJVCVTJgBsAAABLgAFFAUJGQAaALMjAA==.Noobmonkey:BAACLgAFFH8ZAAIaAAUJsyMnBAAFAgAaAAUJsyMnBAAFAgAuAAQKfzMAAhoACQn4JbYAAGoDABoACQn4JbYAAGoDAAAA.Noobwarr:BAAALgAECgYJBgABLgAFFAUJGQAaALMjAA==.Novax:BAAALgAECgMJAwAAAA==.',
Nu='Numeral:BAABLgAFFH8GAAMZAAIJsBFIIgCiAAAZAAIJsBFIIgCiAAALAAIJtw32DQCOAAAAAA==.',
Ol='Olegregg:BAAALgADCgUJCAAAAA==.',
On='Onzynn:BAAALgADCgYJBgAAAA==.',
Pa='Paracelsus:BAAALgAECgYJCwAAAA==.',
Pe='Pepka:BAAALgAECgYJCwAAAA==.',
Ph='Phillcollins:BAABLgAECn8aAAMFAAYJkxBjWQAbAQAFAAYJkxBjWQAbAQAVAAEJhgyyiAAwAAABLgAECgcJFwAeAEwUAA==.',
Pi='Pinktide:BAAALgAECgYJDAABLgAFFAYJHgAFAEEeAA==.',
Po='Pouka:BAAALgAECggJCAABLgAECgkJLwAMAKUlAA==.Power:BAAALgADCgcJBwAAAA==.',
Pr='Prettypoison:BAABLgAECn8fAAIYAAcJmBfGUQB/AQAYAAcJmBfGUQB/AQAAAA==.',
Pu='Putz:BAABLgAECn8/AAMQAAkJ/iJVCAD2AgAQAAkJ/iJVCAD2AgAfAAEJ6hHkKgAyAAAAAA==.',
Ra='Raditz:BAAALgADCgYJBgABLgAFFAYJHgAFAEEeAA==.Rainbow:BAABLgAECn8mAAIcAAgJcR79DQCIAgAcAAgJcR79DQCIAgABLgAECgkJMwAVACMlAA==.Rastasham:BAAALgAECgcJDQAAAA==.Ratfondler:BAACLgAFFH8FAAMbAAMJRxXCFwDgAAAbAAMJRxXCFwDgAAAcAAEJcwYpRgAvAAAuAAQKfywAAxsACQlOI2UCADUDABsACQlOI2UCADUDABwABAlSDzZUAMAAAAAA.',
Re='Reialaleigh:BAAALgAECgMJBgAAAA==.',
Ri='Ricanthetank:BAAALgAECgQJBAAAAA==.',
Ry='Rysho:BAAALgAECgEJAQAAAA==.',
Sa='Sabeam:BAACLgAFFH8VAAIQAAUJTBefCQCQAQAQAAUJTBefCQCQAQAuAAQKfzAAAhAACQnwH84HAE0DABAACQnwH84HAE0DAAAA.Saberdiva:BAABLgAECn8rAAIGAAgJYxEHegBaAQAGAAgJYxEHegBaAQAAAA==.Sabersidious:BAAALgADCgUJBQAAAA==.Saberthyr:BAAALgADCgkJEQAAAA==.Saberwookie:BAAALgADCgUJBQAAAA==.Sabs:BAAALgAFFAIJAgABLgAFFAUJFQAQAEwXAA==.Sagesteppe:BAAALgAECgUJCQAAAA==.Santhon:BAAALgAECgEJAwAAAA==.',
Sc='Scotticus:BAABLgAECn8jAAICAAgJKg/ueABLAQACAAgJKg/ueABLAQAAAA==.',
Se='Seditionist:BAABLgAECn8cAAIVAAYJ+gQ3WQCpAAAVAAYJ+gQ3WQCpAAAAAA==.Sellis:BAAALgADCgEJAQAAAA==.',
Sh='Shakira:BAAALgADCgkJCQABLgAECgMJBgARAAAAAA==.Shammywow:BAAALgADCgEJAQAAAA==.Shamon:BAAALgAECgkJBQAAAA==.Shinju:BAAALgADCgUJBQAAAA==.Shåtheed:BAAALgADCgYJBgAAAA==.',
Si='Sidthekid:BAAALgAECgIJAgAAAA==.Sinayion:BAABLgAECn8dAAISAAcJnwQmKQCiAAASAAcJnwQmKQCiAAAAAA==.',
Sl='Sluggina:BAAALgAECgIJAwAAAA==.',
St='Stepdemonh:BAAALgADCgkJEwAAAA==.Stinkoman:BAAALgAECgQJBwABLgAECgQJCAARAAAAAA==.',
Su='Sunarena:BAABLgAECn8fAAIGAAkJJg8YcABuAQAGAAkJJg8YcABuAQAAAA==.',
Ta='Tankobell:BAABLgAECn8bAAIGAAkJBhEtRADbAQAGAAkJBhEtRADbAQAAAA==.Tavius:BAAALgADCgEJAQAAAA==.',
Te='Terrible:BAEALgAECgcJAQABLgAFFAUJGQAIACwiAA==.',
Th='Thannatos:BAAALgAECgEJAQAAAA==.Thejuiciest:BAAALgADCgEJAgAAAA==.',
To='Tommet:BAAALgADCgUJBQAAAA==.Toukadh:BAAALgAECgYJAQAAAA==.',
Tr='Truart:BAAALgAECgQJCQAAAA==.',
Tu='Tuerjoie:BAABLgAECn8kAAIDAAgJQhiYQgD4AQADAAgJQhiYQgD4AQAAAA==.',
Tw='Twíla:BAAALgADCgYJCwAAAA==.',
Ty='Tywin:BAAALgAECgMJAwAAAA==.',
Uh='Uh:BAAALgADCgYJDAAAAA==.',
Ut='Utopia:BAAALgAECgQJAwAAAA==.',
Va='Valesko:BAAALgAECgcJDwAAAA==.Varfus:BAACLgAFFH8eAAIfAAYJhyVSAAAYAgAfAAYJhyVSAAAYAgAuAAQKfzMAAh8ACQlKJjgAAGoDAB8ACQlKJjgAAGoDAAAA.',
Ve='Velentre:BAAALgAECgYJCAAAAA==.',
Vi='Vichy:BAAALgAECgYJCQAAAA==.Vikstyn:BAAALgAECgEJBAAAAA==.',
Vu='Vulquin:BAAALgAECgUJBQAAAA==.',
We='Weather:BAAALgAECgYJCAAAAA==.',
Wi='Wigskid:BAAALgADCgEJAQAAAA==.Winney:BAABLgAECn8YAAIGAAcJGiSyIwCaAgAGAAcJGiSyIwCaAgAAAA==.',
Wo='Wolfjob:BAAALgADCgUJBQAAAA==.Wouka:BAABLgAECn8vAAMMAAkJpSW/AwBGAwAMAAkJkyW/AwBGAwAJAAYJqiPVAwBQAgAAAA==.',
Wu='Wukong:BAAALgADCgMJAwAAAA==.',
Ya='Yarlyah:BAAALgADCgkJDgAAAA==.',
Yo='Yoyomba:BAAALgAECgUJBQABLgAECggJIwAbAC8aAA==.',
Za='Zargonia:BAAALgAECgEJAQAAAA==.Zaria:BAAALgADCgUJBQAAAA==.',
Ze='Zeposo:BAABLgAECn8ZAAMLAAcJahclIQCWAQALAAcJahclIQCWAQAZAAEJyAQYeQAnAAABLgAECgkJPwAFAN0bAA==.Zeppo:BAAALgAECgIJAgABLgAECgkJPwAFAN0bAA==.Zeptide:BAABLgAECn8/AAMFAAkJ3RsTEACmAgAFAAkJ3RsTEACmAgAVAAcJrRFvMABQAQAAAA==.Zervish:BAAALgAECgEJAQAAAA==.',
Zo='Zoli:BAAALgAECggJCwAAAA==.',
Zr='Zrichfu:BAAALgADCgIJAgABLgAFFAMJBQAMALoFAA==.',
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
