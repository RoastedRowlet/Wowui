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

local lookup = {'Druid-Restoration','DeathKnight-Unholy','Mage-Frost','Mage-Arcane','Shaman-Restoration','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Warlock-Affliction','Shaman-Enhancement','Priest-Holy','Warlock-Demonology','DeathKnight-Blood','Hunter-Survival','Hunter-Marksmanship','Unknown-Unknown','DemonHunter-Havoc','Warlock-Destruction','Shaman-Elemental','DemonHunter-Devourer','Priest-Discipline','Hunter-BeastMastery','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Paladin-Holy','Paladin-Protection','Priest-Shadow','Evoker-Augmentation','DemonHunter-Vengeance',}
local provider = {region='US',realm='Smolderthorn',name='US',type='weekly',zone=46,date='2026-05-16',data={Ac='Achoo:BAAALgAECgQJBwAAAA==.',
Ai='Aitnd:BAAALgADCggJDgAAAA==.Aitns:BAAALgADCgUJBQAAAA==.',
Al='Alduinn:BAAALgADCggJEAAAAA==.',
Am='Amilde:BAAALgAECgkJEQABLgAFFAMJBQABADAOAA==.Amongor:BAABLgAECn8YAAICAAYJ3h95UAAAAgACAAYJ3h95UAAAAgAAAA==.',
An='Anarisa:BAABLgAECn8tAAMDAAkJyRM+NwD7AQADAAkJyRM+NwD7AQAEAAUJcRGGCwAeAQAAAA==.',
Aq='Aquatide:BAAALgAECgYJBgABLgAFFAUJHAAFANkfAA==.',
Ar='Artoria:BAAALgADCgkJCwAAAA==.',
At='Athorama:BAAALgAECgQJBwAAAA==.Atra:BAAALgAECgEJAQAAAA==.',
Av='Avelise:BAABLgAECn8UAAIDAAcJkBelaQADAgADAAcJkBelaQADAgABLgAFFAMJBQABADAOAA==.Averse:BAACLgAFFH8JAAICAAMJ8hhqXACpAAACAAMJ8hhqXACpAAAuAAQKfywAAgIACQnOHHEVAIcCAAIACQnOHHEVAIcCAAAA.',
Az='Azazygos:BAAALgAECgMJAwAAAA==.',
Ba='Baeloth:BAAALgADCgcJDAAAAA==.Barkknight:BAEALgAECggJAwABLgAFFAIJBgAGABsLAA==.Barley:BAAALgAECgEJAQAAAA==.Bauce:BAAALgAECgYJBgAAAA==.',
Be='Bearretheon:BAAALgADCgEJAQAAAA==.Benchtally:BAAALgAECgYJDAAAAA==.Bepid:BAABLgAECn89AAMHAAkJuyPGBwAnAgAHAAYJUSHGBwAnAgAIAAcJsSLVKQASAgAAAA==.',
Bl='Bluetide:BAACLgAFFH8cAAIFAAUJ2R8rCADFAQAFAAUJ2R8rCADFAQAuAAQKfykAAgUACQmOJiQAAOwDAAUACQmOJiQAAOwDAAAA.',
Br='Brokemav:BAABLgAECn8vAAIJAAcJESGWAgCTAgAJAAcJESGWAgCTAgAAAA==.Brooklin:BAABLgAECn8yAAIDAAkJnh4wIwBSAgADAAkJnh4wIwBSAgAAAA==.',
Bu='Busky:BAABLgAECn8fAAMFAAkJAhVaKwDfAQAFAAkJAhVaKwDfAQAKAAEJtRPoJAA8AAAAAA==.',
Ca='Carboncredit:BAABLgAECn8iAAIKAAkJrBAICgAyAgAKAAkJrBAICgAyAgAAAA==.Cassiopea:BAABLgAECn8YAAILAAcJ7BzcEgD9AQALAAcJ7BzcEgD9AQAAAA==.Caysia:BAABLgAFFH8FAAIBAAMJMA4tLADGAAABAAMJMA4tLADGAAAAAA==.',
Ce='Cellcept:BAAALgAECgUJCwAAAA==.',
Ch='Chareth:BAABLgAECn8oAAIDAAkJNwomUACrAQADAAkJNwomUACrAQAAAA==.Charlee:BAAALgADCgcJBwAAAA==.Chaunticleer:BAAALgAECgcJCwAAAA==.Chinchillada:BAAALgAECgUJDwAAAA==.',
Co='Coldbrewed:BAAALgAECgYJBgAAAA==.Cowladin:BAAALgADCgYJBgABLgAECggJFQAMAAMeAA==.',
Cr='Crossover:BAAALgADCgYJBgAAAA==.',
['Cà']='Càss:BAAALgAECgQJAgAAAA==.',
Da='Dabajabaza:BAABLgAECn8iAAINAAgJBwlHIwDTAAANAAgJBwlHIwDTAAAAAA==.Dabergerak:BAACLgAFFH8GAAIIAAMJXCHSGQAQAQAIAAMJXCHSGQAQAQAuAAQKfysAAggACQmbJfYAAFwDAAgACQmbJfYAAFwDAAAA.Daenys:BAAALgAECgMJAwABLgAFFAcJJAAJAM0YAA==.Daggart:BAAALgAECgkJCQAAAA==.Dakrus:BAACLgAFFH8FAAIOAAMJmg13FADvAAAOAAMJmg13FADvAAAuAAQKfyUAAw8ACQkwGVIgACMCAA8ACAmpFlIgACMCAA4ABgk9DmkgAEwBAAAA.Darthßsaber:BAAALgADCgUJBQAAAA==.Dawin:BAAALgAECgIJAgAAAA==.Dax:BAAALgADCgYJBgAAAA==.',
De='Deadazz:BAAALgAECgYJEwABLgAECgkJOAAMAIoeAA==.Deeiinndu:BAAALgADCgMJCQAAAA==.Dejanira:BAABLgAECn8gAAIBAAkJzhFcMQCUAQABAAkJzhFcMQCUAQAAAA==.Demonslayerr:BAAALgADCgMJAwAAAA==.Demotope:BAAALgADCgcJDAABLgAECgYJDAAQAAAAAA==.',
Di='Diddily:BAAALgAECgcJEgAAAA==.Diesverdi:BAAALgAECgMJAwAAAA==.Dirtylilskin:BAAALgADCgkJHQAAAA==.',
Do='Dookie:BAAALgAECgQJBAAAAA==.',
Dr='Draconae:BAABLgAECn8UAAIRAAYJfgaNPQAHAQARAAYJfgaNPQAHAQAAAA==.Dracotope:BAAALgAECgYJDAAAAA==.Dragonjoy:BAABLgAECn8kAAINAAkJNxYlEQCAAQANAAkJNxYlEQCAAQAAAA==.Drathier:BAAALgAECgIJAgAAAA==.Dridarok:BAABLgAECn8aAAIIAAkJxwrfIwCJAQAIAAkJxwrfIwCJAQAAAA==.',
Ei='Eighttyhd:BAAALgADCgQJBAAAAA==.Eightyhd:BAAALgADCgIJAgAAAA==.Eirny:BAAALgAECgMJBAAAAA==.',
El='Element:BAAALgADCgEJAQAAAA==.Elise:BAABLgAECn8kAAMSAAkJQhckCQAvAgASAAgJzBckCQAvAgAJAAgJARH4DgBBAQAAAA==.Elstrid:BAABLgAECn8VAAIMAAgJAx43PAAcAgAMAAgJAx43PAAcAgAAAA==.',
Er='Erzaflame:BAAALgADCgEJAQAAAA==.',
Eu='Euphoria:BAAALgADCgcJDAABLgAECgkJMQATACMlAA==.',
Ev='Evochre:BAAALgAECgUJCQAAAA==.',
Fa='Faerine:BAAALgADCgcJBwAAAA==.Fantasy:BAABLgAECn8xAAITAAkJIyV7AQBNAwATAAkJIyV7AQBNAwAAAA==.',
Fe='Felbourn:BAABLgAECn8aAAMRAAgJhCGOCADZAgARAAgJhCGOCADZAgAUAAIJuwlvzABdAAAAAA==.Fendraim:BAAALgAECgQJBAABLgAECgcJEQAQAAAAAA==.',
Fi='Figurefour:BAAALgAECgkJDwAAAA==.',
Fo='Foedris:BAAALgADCgUJBQAAAA==.Foxfire:BAAALgAECgQJCAAAAA==.',
Fr='Frailboosy:BAABLgAECn9DAAIGAAkJPiH8BwD5AgAGAAkJPiH8BwD5AgAAAA==.Fri:BAAALgADCgkJCQAAAA==.Frigamortis:BAAALgAECgQJBQAAAA==.',
Ge='Gemini:BAAALgADCgcJDAAAAA==.',
Gi='Gilferno:BAAALgAECgQJBAAAAA==.',
Gl='Glitz:BAABLgAFFH8FAAIDAAUJawSpTgAMAQADAAUJawSpTgAMAQABLgAFFAYJDwAVAMwGAA==.',
Gn='Gnarfok:BAAALgAECgQJDgAAAA==.',
Go='Goopster:BAAALgADCgcJCQABLgAECgIJAgAQAAAAAA==.',
Gr='Graamps:BAAALgAECgUJCAAAAA==.Gravedigger:BAABLgAECn8wAAINAAkJ2h8SBQBRAgANAAkJ2h8SBQBRAgAAAA==.',
Gu='Gust:BAAALgAECgQJDwAAAA==.',
Ha='Hatredx:BAAALgADCgIJAgAAAA==.',
He='Heisenberg:BAAALgAECgEJAQABLgAECggJIQAWAIoaAA==.',
Ho='Holywagyu:BAAALgAECgYJBgAAAA==.',
Hy='Hyõrinmaru:BAAALgAECgMJAwAAAA==.',
In='Inarios:BAABLgAECn8fAAMVAAgJ/h32BwCrAgAVAAgJ/h32BwCrAgALAAEJtwzrWwAqAAAAAA==.Inshape:BAAALgAECgYJEwAAAA==.',
Ir='Ironnman:BAAALgAECgEJAQABLgAECgkJGQAXAHEYAA==.Ironnmonk:BAABLgAECn8ZAAQXAAkJcRiBGwAnAgAXAAkJcRiBGwAnAgAYAAEJihGabgA1AAAZAAEJUgQwdQAcAAAAAA==.',
Ja='Javlin:BAAALgAECgEJAgAAAA==.',
Jo='Joltarin:BAAALgAECgEJAQABLgAECggJFQAMAAMeAA==.',
Ju='Jujufya:BAAALgADCgYJBgABLgAECgcJEAAQAAAAAA==.Jujukni:BAAALgAECgMJAwABLgAECgcJEAAQAAAAAA==.Jujumon:BAAALgAECgcJEAAAAA==.Jujuzul:BAAALgADCgUJBgABLgAECgcJEAAQAAAAAA==.Justimp:BAABLgAECn8iAAIMAAkJOxPzMQDTAQAMAAkJOxPzMQDTAQAAAA==.',
Ka='Kanon:BAAALgAECgYJCwAAAA==.Kanook:BAAALgAECgMJAwAAAA==.Karlek:BAABLgAFFH8FAAIaAAMJ2gTFJACuAAAaAAMJ2gTFJACuAAAAAA==.',
Ki='Kikily:BAAALgADCgkJCQAAAA==.',
Ko='Konsistency:BAABLgAECn8fAAIUAAcJlA6icgBNAQAUAAcJlA6icgBNAQAAAA==.Konviction:BAABLgAECn8fAAMGAAkJ/RH0VgB/AQAGAAkJ/RH0VgB/AQAbAAIJZwJ1QQAdAAAAAA==.',
Kr='Krogg:BAAALgADCgcJBwAAAA==.',
La='Lalana:BAAALgAECgUJDwAAAA==.Lan:BAAALgADCgEJAQAAAA==.Landin:BAAALgAECgcJBwAAAA==.',
Li='Liari:BAEBLgAECn8VAAIDAAgJOwjHjgAhAQADAAgJOwjHjgAhAQABLgAFFAIJBgAGABsLAA==.Libra:BAAALgADCgEJAQAAAA==.Lilith:BAACLgAFFH8PAAMVAAYJzAaWDgCSAQAVAAYJzAaWDgCSAQAcAAMJfQibHwCUAAAuAAQKfyEAAxUACQmpGG4SACECABUACAk0GW4SACECABwABwmVHEghAGkBAAAA.Lithari:BAAALgADCggJCAAAAA==.',
Lo='Lofwyr:BAACLgAFFH8FAAIdAAMJyQFZMgCkAAAdAAMJyQFZMgCkAAAuAAQKfyoAAh0ACQm9EIgYAMUBAB0ACQm9EIgYAMUBAAAA.Lootadots:BAAALgADCgkJHAABLgAECgYJEgAQAAAAAA==.',
Lu='Lumie:BAABLgAECn8mAAMLAAkJBCCgCADCAgALAAkJBCCgCADCAgAcAAcJ4BFkIwBZAQAAAA==.Lumiea:BAAALgAECgEJAQABLgAECgkJJgALAAQgAA==.Lunie:BAABLgAECn8bAAIBAAgJuB7PDgCgAgABAAgJuB7PDgCgAgABLgAECgkJJgALAAQgAA==.',
Ma='Magadeoz:BAAALgAECgYJDQAAAA==.Magicshow:BAABLgAECn8cAAIDAAgJ9RD8lACqAQADAAgJ9RD8lACqAQAAAA==.Malzahar:BAAALgADCgEJAgAAAA==.',
Mc='Mcdracula:BAAALgAECgcJDQAAAA==.',
Mi='Milfred:BAAALgADCggJCAAAAA==.Mistrniceguy:BAAALgAECgEJAQAAAA==.',
Mo='Moarticia:BAAALgAECgYJCwAAAA==.Moonbelle:BAAALgAECgcJDAABLgAFFAYJDwAVAMwGAA==.',
Mu='Murthius:BAAALgADCgYJBgAAAA==.Musky:BAAALgAECgEJAgAAAA==.',
My='Myoushi:BAAALgADCgEJAQAAAA==.',
Na='Naâmah:BAAALgAECgUJBQAAAA==.',
Ne='Necromachine:BAABLgAECn8ZAAMCAAgJrhm3XQDZAQACAAgJrhm3XQDZAQANAAIJVwZ/PgBWAAAAAA==.Neiry:BAAALgADCgcJBwAAAA==.',
No='Noctislucis:BAABLgAECn8aAAMUAAkJqgrfcADvAAAUAAcJpAnfcADvAAAeAAYJkQoqGQDRAAAAAA==.Noj:BAAALgADCgUJBQAAAA==.Noobdk:BAAALgAFFAIJBAABLgAFFAQJGAAXAMolAA==.Noobmonkey:BAACLgAFFH8YAAIXAAQJyiWHBQC7AQAXAAQJyiWHBQC7AQAuAAQKfzMAAhcACQn4JYIAAG4DABcACQn4JYIAAG4DAAAA.Noobwarr:BAAALgAECgYJBgABLgAFFAQJGAAXAMolAA==.Novax:BAAALgAECgMJAwAAAA==.',
Nu='Numeral:BAABLgAFFH8GAAMcAAIJsBEGHQClAAAcAAIJsBEGHQClAAALAAIJtw32DQCOAAAAAA==.',
Ol='Olegregg:BAAALgADCgUJCAAAAA==.',
Pa='Paracelsus:BAAALgAECgYJCwAAAA==.',
Pe='Pepka:BAAALgAECgYJCwAAAA==.',
Ph='Phillcollins:BAAALgAECgUJDQABLgAECgcJHgAXAN0MAA==.',
Pi='Pinktide:BAAALgAECgYJDAABLgAFFAUJHAAFANkfAA==.',
Po='Power:BAAALgADCgcJBwAAAA==.',
Pr='Prettypoison:BAABLgAECn8cAAIWAAYJwBisUgBSAQAWAAYJwBisUgBSAQAAAA==.',
Pu='Putz:BAABLgAECn86AAMUAAkJ2SBgDACpAgAUAAkJ2SBgDACpAgAeAAEJ6hESJQAzAAAAAA==.',
Ra='Raditz:BAAALgADCgYJBgABLgAFFAUJHAAFANkfAA==.Rainbow:BAABLgAECn8iAAIZAAgJ6BvADgBQAgAZAAgJ6BvADgBQAgABLgAECgkJMQATACMlAA==.Rastasham:BAAALgAECgYJBgAAAA==.Ratfondler:BAACLgAFFH8FAAMYAAMJRxU8EwDmAAAYAAMJRxU8EwDmAAAZAAEJcwaWNwAwAAAuAAQKfyMAAxgACQmTIAEFAMkCABgACQmTIAEFAMkCABkABAlQD/9DAMEAAAAA.',
Re='Reialaleigh:BAAALgAECgMJAwAAAA==.',
Ri='Ricanthetank:BAAALgAECgQJBAAAAA==.',
Ry='Rysho:BAAALgAECgEJAQAAAA==.',
Sa='Sabeam:BAACLgAFFH8VAAIUAAUJTBefCQCQAQAUAAUJTBefCQCQAQAuAAQKfzAAAhQACQnwH84HAE0DABQACQnwH84HAE0DAAAA.Saberdiva:BAABLgAECn8pAAIGAAgJBhGVbwBFAQAGAAgJBhGVbwBFAQAAAA==.Saberthyr:BAAALgADCgkJEQAAAA==.Saberwookie:BAAALgADCgUJBQAAAA==.Sagesteppe:BAAALgAECgQJBAAAAA==.',
Sc='Scotticus:BAABLgAECn8jAAICAAgJKg9lYwBZAQACAAgJKg9lYwBZAQAAAA==.',
Se='Seditionist:BAABLgAECn8WAAITAAYJWgTzTgClAAATAAYJWgTzTgClAAAAAA==.Sellis:BAAALgADCgEJAQAAAA==.',
Sh='Shakira:BAAALgADCgkJCQABLgAECgMJAwAQAAAAAA==.Shammywow:BAAALgADCgEJAQAAAA==.Shamon:BAAALgAECgkJBQAAAA==.Shinju:BAAALgADCgUJBQAAAA==.',
Si='Sidthekid:BAAALgAECgIJAgAAAA==.Sinayion:BAABLgAECn8aAAIbAAYJsgSnKACDAAAbAAYJsgSnKACDAAAAAA==.',
Sl='Sluggina:BAAALgAECgIJAwAAAA==.',
St='Stepdemonh:BAAALgADCgkJEwAAAA==.Stinkoman:BAAALgAECgQJBwABLgAECgQJCAAQAAAAAA==.',
Su='Sunarena:BAABLgAECn8fAAIGAAkJJQ91XwBqAQAGAAkJJQ91XwBqAQAAAA==.',
Ta='Tankobell:BAAALgAFFAEJAQAAAA==.',
Te='Terrible:BAAALgAECgcJAQAAAA==.',
Th='Thannatos:BAAALgADCgEJAQAAAA==.Thejuiciest:BAAALgADCgEJAgAAAA==.',
To='Toukadh:BAAALgAECgYJAQAAAA==.',
Tr='Truart:BAAALgAECgQJCQAAAA==.',
Tu='Tuerjoie:BAABLgAECn8hAAIDAAcJDhcCUQCoAQADAAcJDhcCUQCoAQAAAA==.',
Tw='Twíla:BAAALgADCgYJCwAAAA==.',
Uh='Uh:BAAALgADCgYJDAAAAA==.',
Ut='Utopia:BAAALgAECgQJAwAAAA==.',
Va='Valesko:BAAALgAECgcJCwAAAA==.Varfus:BAACLgAFFH8cAAIeAAUJiSWTAACxAQAeAAUJiSWTAACxAQAuAAQKfzMAAh4ACQlJJh8AAHEDAB4ACQlJJh8AAHEDAAAA.',
Ve='Velentre:BAAALgAECgYJCAAAAA==.',
Vi='Vichy:BAAALgAECgMJBAAAAA==.Vikstyn:BAAALgAECgEJBAAAAA==.',
Vu='Vulquin:BAAALgAECgUJBQAAAA==.',
We='Weather:BAAALgAECgYJCAAAAA==.',
Wi='Wigskid:BAAALgADCgEJAQAAAA==.Winney:BAABLgAECn8WAAIGAAcJGSSyIwCaAgAGAAcJGSSyIwCaAgAAAA==.',
Wo='Wolfjob:BAAALgADCgUJBQAAAA==.Wouka:BAABLgAECn8tAAMMAAkJfiXMAgBHAwAMAAkJbSXMAgBHAwAJAAYJqiPVAwBQAgAAAA==.',
Wu='Wukong:BAAALgADCgMJAwAAAA==.',
Ya='Yarlyah:BAAALgADCgkJDgAAAA==.',
Yo='Yoyomba:BAAALgAECgUJBQAAAA==.',
Za='Zargonia:BAAALgAECgEJAQAAAA==.Zaria:BAAALgADCgUJBQAAAA==.',
Ze='Zeposo:BAABLgAECn8XAAMLAAcJphZJHgCLAQALAAcJphZJHgCLAQAcAAEJyAT9agAnAAABLgAECgkJPwAFAN0bAA==.Zeppo:BAAALgADCgQJBAABLgAECgkJPwAFAN0bAA==.Zeptide:BAABLgAECn8/AAMFAAkJ3RtFDACsAgAFAAkJ3RtFDACsAgATAAcJrRF+KABVAQAAAA==.Zervish:BAAALgAECgEJAQAAAA==.',
Zo='Zoli:BAAALgAECggJAwAAAA==.',
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
