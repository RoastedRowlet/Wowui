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

local lookup = {'Mage-Frost','Monk-Brewmaster','Druid-Restoration','DeathKnight-Unholy','Mage-Arcane','Shaman-Restoration','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Warlock-Affliction','Shaman-Enhancement','Priest-Holy','Warlock-Destruction','Warlock-Demonology','DeathKnight-Blood','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Frost','DemonHunter-Devourer','Unknown-Unknown','Paladin-Protection','DemonHunter-Havoc','Priest-Shadow','Shaman-Elemental','DemonHunter-Vengeance','Priest-Discipline','Hunter-BeastMastery','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','Paladin-Holy','Evoker-Augmentation',}
local provider = {region='US',realm='Smolderthorn',name='US',type='weekly',zone=46,date='2026-06-20',data={Ac='Achoo:BAABLgAECn8YAAIBAAgJCAXC1wDmAAABAAgJCAXC1wDmAAAAAA==.Acorn:BAAALgADCgMJBAAAAA==.',
Ai='Aitnd:BAAALgAECgQJCAAAAA==.Aitns:BAAALgADCgUJBQAAAA==.',
Ak='Akabara:BAAALgAECgQJBwAAAA==.',
Al='Alatyr:BAAALgAECgUJBQABLgAECgkJGgACAHEYAA==.Alduinn:BAAALgADCggJEAAAAA==.',
Am='Amilde:BAAALgAECgkJEQABLgAFFAMJCAADAGkSAA==.Amongor:BAABLgAECn8YAAIEAAYJ3h95UAAAAgAEAAYJ3h95UAAAAgAAAA==.',
An='Anarisa:BAABLgAECn9hAAMBAAkJQyB0EAD4AgABAAkJQyB0EAD4AgAFAAUJcRGGCwAeAQAAAA==.',
Aq='Aquatide:BAAALgAECgYJBgABLgAFFAgJIgAGAAQeAA==.',
Ar='Arcaz:BAAALgAECgEJAQAAAA==.Artoria:BAAALgADCgkJCwAAAA==.',
At='Athorama:BAAALgAECgUJCwAAAA==.Atra:BAAALgAECgEJAQAAAA==.',
Av='Avelise:BAABLgAECn8UAAIBAAcJkBelaQADAgABAAcJkBelaQADAgABLgAFFAMJCAADAGkSAA==.Averse:BAACLgAFFH8ZAAIEAAUJzh+SSQBgAQAEAAUJzh+SSQBgAQAuAAQKfzUAAgQACQk0HrQYALICAAQACQk0HrQYALICAAAA.',
Az='Azazygos:BAAALgAECgMJAwAAAA==.',
Ba='Baeloth:BAAALgADCgcJDAAAAA==.Barkknight:BAEALgAECgkJBQABLgAFFAUJFAAHAMMQAA==.Barley:BAAALgAECgUJBQAAAA==.Bauce:BAAALgAECgYJBgAAAA==.',
Be='Bearretheon:BAAALgADCgEJAQAAAA==.Benchtally:BAAALgAECgYJDAAAAA==.Bepizo:BAACLgAFFH8UAAMIAAUJpx9KBQCcAAAJAAMJyh1oAwCiAAAIAAMJHxpKBQCcAAAuAAQKf0YAAwkACQndJF4KAEUCAAkABgnSIl4KAEUCAAgABwmzItUpABICAAAA.',
Bl='Bluetide:BAACLgAFFH8iAAIGAAgJBB4ZAwCuAgAGAAgJBB4ZAwCuAgAuAAQKfykAAgYACQmOJo8AAOEDAAYACQmOJo8AAOEDAAAA.',
Br='Brokemav:BAABLgAECn8vAAIKAAcJESGWAgCTAgAKAAcJESGWAgCTAgAAAA==.Brooklin:BAABLgAECn8yAAIBAAkJnh7dKwDDAgABAAkJnh7dKwDDAgAAAA==.',
Bu='Busky:BAABLgAECn8lAAMGAAkJAhVaKwDfAQAGAAkJAhVaKwDfAQALAAcJkhHVFwBLAQAAAA==.',
Ca='Carboncredit:BAABLgAECn8iAAILAAkJrRAICgAyAgALAAkJrRAICgAyAgAAAA==.Cassiopea:BAABLgAECn8ZAAIMAAgJ7hqnGAAHAgAMAAgJ7hqnGAAHAgAAAA==.Caysia:BAABLgAFFH8IAAIDAAMJaRLAQQCqAAADAAMJaRLAQQCqAAAAAA==.',
Ce='Cellcept:BAABLgAECn8XAAINAAUJGh4oDgBaAQANAAUJGh4oDgBaAQAAAA==.',
Ch='Chareth:BAABLgAECn8oAAIBAAkJNgo/cQCXAQABAAkJNgo/cQCXAQAAAA==.Charlee:BAAALgADCgcJBwAAAA==.Chaunticleer:BAAALgAECgcJCwAAAA==.Chesumadre:BAAALgADCgMJBAAAAA==.Chinchillada:BAABLgAECn8hAAIBAAgJLxQVWgDPAQABAAgJLxQVWgDPAQAAAA==.',
Ci='Cinderfal:BAAALgAECgEJAgAAAA==.',
Cl='Claggor:BAAALgAECgMJAwAAAA==.',
Co='Coldbrewed:BAAALgAECgYJBgAAAA==.Cowladin:BAAALgADCgYJBgABLgAECggJHwAOADcfAA==.',
Cr='Crossover:BAAALgADCgYJBgAAAA==.',
['Cà']='Càss:BAAALgAECgQJBQABLgAECggJGQAMAO4aAA==.',
Da='Dabajabaza:BAABLgAECn83AAIPAAkJ1QpjIwA4AQAPAAkJ1QpjIwA4AQAAAA==.Dabergerak:BAACLgAFFH8JAAIIAAMJXCFwLgD4AAAIAAMJXCFwLgD4AAAuAAQKfysAAggACQmcJWEDADUDAAgACQmcJWEDADUDAAAA.Daenys:BAAALgAECgMJAwABLgAFFAgJLAAKAA0bAA==.Daggart:BAAALgAECgkJDgAAAA==.Dagrimreaper:BAAALgADCgcJBgABLgAECgcJFAAKALsdAA==.Daila:BAAALgAECgEJAgAAAA==.Dakrus:BAACLgAFFH8FAAIQAAMJmg2WIQDNAAAQAAMJmg2WIQDNAAAuAAQKfyUAAxEACQkwGVIgACMCABEACAmpFlIgACMCABAABgk9DlEsAEEBAAAA.Dankestacorn:BAAALgADCggJCgAAAA==.Darthßsaber:BAAALgADCgUJBQAAAA==.Dax:BAAALgADCgYJBgAAAA==.',
De='Deadazz:BAABLgAECn8aAAMSAAcJCQ0eFgAoAQASAAcJCQ0eFgAoAQAPAAYJCgStQwCAAAABLgAFFAYJCwAOADwNAA==.Deadputz:BAAALgAECggJEwABLgAFFAMJBwATAFYaAA==.Deeiinnduh:BAAALgAECgYJBgAAAA==.Dein:BAAALgAECgcJEQAAAA==.Dejanira:BAABLgAECn8gAAIDAAkJzhFrQACQAQADAAkJzhFrQACQAQAAAA==.Demonslayerr:BAAALgADCgQJBAAAAA==.Demotope:BAAALgADCgcJDAABLgAECgYJDAAUAAAAAA==.',
Di='Diddily:BAABLgAECn8VAAMVAAgJWxUTHwAQAQAVAAgJWxUTHwAQAQAHAAIJ7QMtxAEiAAAAAA==.Diesverdi:BAAALgAECgMJAwAAAA==.Dirtylilskin:BAAALgADCgkJHQAAAA==.',
Do='Dookie:BAAALgAECgQJBAAAAA==.',
Dr='Draconae:BAABLgAECn8bAAIWAAYJWQf8PgC6AAAWAAYJWQf8PgC6AAAAAA==.Dracotope:BAAALgAECgYJDAAAAA==.Dragonjoy:BAABLgAECn8kAAIPAAkJORbpFgCwAQAPAAkJORbpFgCwAQAAAA==.Drathier:BAAALgAECgIJAgAAAA==.Dridarok:BAABLgAECn8gAAIIAAkJqQyDLgCWAQAIAAkJqQyDLgCWAQAAAA==.',
['Dâ']='Dâwn:BAABLgAECn8WAAIXAAgJlQW6RQD4AAAXAAgJlQW6RQD4AAAAAA==.',
Ei='Eighttyhd:BAAALgADCgQJBAAAAA==.Eightyhd:BAAALgADCgIJAgAAAA==.Eirny:BAAALgAECgMJBAAAAA==.',
El='Element:BAAALgADCgEJAQABLgAFFAUJFAAIAKcfAA==.Elise:BAABLgAECn8kAAMNAAkJQhckCQAvAgANAAgJzBckCQAvAgAKAAgJARH4DgBBAQAAAA==.Elstrid:BAABLgAECn8fAAMOAAgJNx8uMQAUAgAOAAgJNx8uMQAUAgANAAEJAACgVQAAAAAAAA==.',
Er='Erzaflame:BAAALgADCgEJAQAAAA==.',
Eu='Euphoria:BAAALgAECgMJAwABLgAECgkJOQAYAFQmAA==.',
Ev='Evochre:BAAALgAECgUJCQAAAA==.',
Fa='Faelgalus:BAAALgAECgIJAgAAAA==.Faerine:BAAALgADCgcJBwAAAA==.Fantasy:BAABLgAECn85AAIYAAkJVCZHAwA7AwAYAAkJVCZHAwA7AwAAAA==.',
Fe='Felbourn:BAACLgAFFH8IAAIWAAMJvxmAFwDnAAAWAAMJvxmAFwDnAAAuAAQKfyAABBYACQlkIY4IANkCABYACAmJIY4IANkCABkAAgktFiQiAIwAABMAAgm7CW/MAF0AAAAA.Fendraim:BAAALgAECgYJCwABLgAECgcJEQAUAAAAAA==.',
Fi='Figurefour:BAAALgAECgkJDwAAAA==.',
Fo='Foedris:BAAALgADCgUJBQAAAA==.Forste:BAAALgAECgUJBQAAAA==.Foxfire:BAAALgAECgQJCAAAAA==.',
Fr='Frailboosy:BAACLgAFFH8PAAIHAAQJ0RZpQgAmAQAHAAQJ0RZpQgAmAQAuAAQKf1sAAgcACQkYIvYLAAUDAAcACQkYIvYLAAUDAAAA.Fri:BAAALgADCgkJCQAAAA==.Frigamortis:BAAALgAECgYJEQAAAA==.',
Ga='Galnas:BAAALgADCgcJBwABLgAECgIJAgAUAAAAAA==.',
Ge='Gemini:BAAALgAECgQJBAAAAA==.',
Gi='Gilferno:BAAALgAECgQJBAAAAA==.',
Gl='Glitz:BAABLgAFFH8FAAIBAAUJawTeeADnAAABAAUJawTeeADnAAABLgAFFAYJEQAaAMwGAA==.',
Gn='Gnarfok:BAAALgAECgQJDwAAAA==.',
Go='Goopster:BAAALgADCgcJCQAAAA==.',
Gr='Graamps:BAAALgAECgYJDQAAAA==.Gravedigger:BAACLgAFFH8RAAMPAAQJuBsyFgA5AQAPAAQJuBsyFgA5AQASAAEJZADFLgAoAAAuAAQKfzQAAg8ACQncHyQKAHACAA8ACQncHyQKAHACAAAA.',
Gu='Gunde:BAAALgAECgkJBQAAAA==.Gust:BAAALgAECgQJDwAAAA==.',
Ha='Hatredx:BAAALgADCgIJAgAAAA==.',
He='Heisenberg:BAAALgAECgQJCAABLgAFFAQJDwAbAHsRAA==.',
Ho='Holywagyu:BAAALgAECgYJBgAAAA==.',
Hy='Hyllinia:BAAALgADCgEJAQAAAA==.Hyõrinmaru:BAAALgAECgMJAwAAAA==.',
Ih='Iheal:BAAALgAECgEJAQAAAA==.',
In='Inarios:BAABLgAECn8qAAQaAAkJhxuJDQCVAgAaAAgJ/h2JDQCVAgAXAAQJlhUNPwAVAQAMAAEJtwzJdQAkAAAAAA==.Inshape:BAAALgAECgYJEwAAAA==.',
Ir='Ironnman:BAAALgAECgEJAQABLgAECgkJGgACAHEYAA==.Ironnmonk:BAABLgAECn8aAAQCAAkJcRiBGwAnAgACAAkJcRiBGwAnAgAcAAEJihEMnQAyAAAdAAEJUgQwdQAcAAAAAA==.',
Ja='Javlin:BAAALgAECgYJEAAAAA==.',
Jo='Joltarin:BAAALgAECgEJAQABLgAECggJHwAOADcfAA==.',
Ju='Jujufya:BAAALgAECgIJAgABLgAECggJEgAUAAAAAA==.Jujujab:BAAALgADCgMJAwABLgAECggJEgAUAAAAAA==.Jujukni:BAAALgAECgUJDQABLgAECggJEgAUAAAAAA==.Jujumon:BAAALgAECggJEgAAAA==.Jujuzap:BAAALgADCgEJAQABLgAECggJEgAUAAAAAA==.Jujuzul:BAAALgADCgUJBgABLgAECggJEgAUAAAAAA==.Justimp:BAACLgAFFH8GAAIOAAMJTQgFiAC2AAAOAAMJTQgFiAC2AAAuAAQKfyQAAg4ACQl4FMtDANABAA4ACQl4FMtDANABAAAA.',
Ka='Kanon:BAABLgAECn8WAAIeAAkJBxOcEgDCAQAeAAkJBxOcEgDCAQAAAA==.Kanook:BAAALgAECgMJAwAAAA==.Karlek:BAABLgAFFH8GAAMfAAMJ2gToOACHAAAfAAMJ2gToOACHAAAHAAEJ6AEV0AAuAAAAAA==.',
Ke='Kelox:BAAALgAECgEJAQAAAA==.',
Ki='Kikily:BAAALgADCgkJCQAAAA==.',
Ko='Konsistency:BAABLgAECn8fAAITAAcJlA6icgBNAQATAAcJlA6icgBNAQAAAA==.Konviction:BAABLgAECn8fAAMHAAkJ/REKiQBeAQAHAAkJ/REKiQBeAQAVAAIJZwK3WQAcAAAAAA==.Korellon:BAAALgADCgMJAwAAAA==.',
Kr='Kreel:BAAALgAECgIJAwAAAA==.Krogg:BAAALgADCgcJBwAAAA==.',
La='Lalana:BAABLgAECn8iAAIbAAgJOA4bXgCMAQAbAAgJOA4bXgCMAQAAAA==.Lan:BAAALgAECgcJDQAAAA==.Landin:BAAALgAECgcJBwAAAA==.',
Li='Liari:BAECLgAFFH8GAAIBAAMJBwSokwCtAAABAAMJBwSokwCtAAAuAAQKfxwAAgEACAkrCuiRAFQBAAEACAkrCuiRAFQBAAEuAAUUBQkUAAcAwxAA.Libra:BAAALgADCgEJAQAAAA==.Lilith:BAACLgAFFH8RAAMaAAYJzAbHCABRAQAaAAYJzAbHCABRAQAXAAQJcwlVKAC7AAAuAAQKfyEAAxoACQmpGG4SACECABoACAk0GW4SACECABcABwmVHEchAM4BAAAA.Lithari:BAAALgADCggJCAAAAA==.',
Lo='Lofwyr:BAACLgAFFH8FAAIgAAMJyQHRUQCDAAAgAAMJyQHRUQCDAAAuAAQKfzQAAiAACQmjEgkeAOcBACAACQmjEgkeAOcBAAAA.Lootadots:BAAALgAECgEJAQABLgAECgYJGAAIAF4UAA==.',
Lu='Lumes:BAAALgAECgUJBQAAAA==.Lumie:BAABLgAECn8mAAMMAAkJAyCgCADCAgAMAAkJAyCgCADCAgAXAAcJ4BEUNQBDAQABLgAFFAMJBwADAMwPAA==.Lumiea:BAAALgAECgYJBgABLgAFFAMJBwADAMwPAA==.Lunar:BAAALgADCgIJAgABLgAFFAYJEQAaAMwGAA==.Lunie:BAACLgAFFH8HAAIDAAMJzA/3QQCqAAADAAMJzA/3QQCqAAAuAAQKfx0AAgMACAnTHjQSALwCAAMACAnTHjQSALwCAAAA.',
Ma='Magadeoz:BAABLgAECn8UAAIBAAcJ6QrIswAcAQABAAcJ6QrIswAcAQAAAA==.Magicshow:BAACLgAFFH8GAAIBAAMJpQdNjQC/AAABAAMJpQdNjQC/AAAuAAQKfx0AAgEACAn1EPyUAKoBAAEACAn1EPyUAKoBAAAA.Malachite:BAAALgADCgQJBAABLgAFFAYJEQAaAMwGAA==.Malzahar:BAAALgADCgEJAgAAAA==.',
Mc='Mcdracula:BAAALgAECgcJEgAAAA==.',
Mi='Milfred:BAAALgAFFAEJAQAAAA==.Mistrniceguy:BAAALgAECgEJAQAAAA==.',
Mo='Moarticia:BAAALgAECgYJCwABLgAFFAIJBQAgAFkRAA==.Moonbelle:BAAALgAECgcJDAABLgAFFAYJEQAaAMwGAA==.',
Mu='Murthius:BAAALgAECgYJEgAAAA==.Musky:BAAALgAECgEJAgAAAA==.',
My='Myoushi:BAAALgADCgEJAQAAAA==.',
Na='Naâmah:BAAALgAECgUJBQAAAA==.',
Ne='Necromachine:BAACLgAFFH8OAAIEAAQJkg17dgAVAQAEAAQJkg17dgAVAQAuAAQKfxwAAwQACQmYF/B7AGsBAAQACQmYF/B7AGsBAA8AAglXBn8+AFYAAAAA.Neiry:BAAALgADCgcJBwAAAA==.Neon:BAAALgAECgYJDgABLgAECgkJOQAYAFQmAA==.',
No='Noctislucis:BAACLgAFFH8FAAITAAQJnAGcfACEAAATAAQJnAGcfACEAAAuAAQKfyAABBkACQn+CiwaAMwAABMABwmkCVicAOkAABkABwkGCiwaAMwAABYAAQlyACiHAAMAAAAA.Noj:BAAALgADCgUJBQAAAA==.Noobdk:BAABLgAFFH8IAAMEAAQJ5BunDQCoAAAEAAIJLRenDQCoAAAPAAIJVCWXNABmAAABLgAFFAYJGgACAPMiAA==.Noobmonkey:BAACLgAFFH8aAAICAAYJ8yIYBQBJAgACAAYJ8yIYBQBJAgAuAAQKfzMAAgIACQn4JSYBAGIDAAIACQn4JSYBAGIDAAAA.Noobwarr:BAAALgAFFAEJAQABLgAFFAYJGgACAPMiAA==.Novax:BAAALgAECgQJBgAAAA==.',
Nu='Numeral:BAABLgAFFH8GAAMMAAIJtw32DQCOAAAMAAIJtw32DQCOAAAXAAIJsBG5LwCIAAAAAA==.',
Ol='Olegregg:BAAALgADCgUJCAAAAA==.',
On='Onzynn:BAAALgADCgcJCAAAAA==.',
Pa='Paracelsus:BAAALgAECgYJCwAAAA==.',
Pe='Pepka:BAAALgAECgYJCwAAAA==.',
Ph='Phillcollins:BAABLgAECn8pAAMGAAYJfhuTOgDEAQAGAAYJfhuTOgDEAQAYAAYJRhOzRAAgAQABLgAECgcJFwAgAEwUAA==.',
Pi='Pinktide:BAAALgAECgYJDAABLgAFFAgJIgAGAAQeAA==.',
Po='Pouka:BAAALgAECggJCAABLgAECgkJNAAOALslAA==.Power:BAAALgADCgcJBwAAAA==.',
Pr='Prettypoison:BAABLgAECn80AAIbAAkJcxmMJABQAgAbAAkJcxmMJABQAgAAAA==.',
Pu='Putz:BAACLgAFFH8HAAITAAMJVhoHUQD6AAATAAMJVhoHUQD6AAAuAAQKf00AAxMACQlEJDcFADUDABMACQlEJDcFADUDABkAAQnqEaQ0ADIAAAAA.',
Ra='Raditz:BAAALgADCgYJBgABLgAFFAgJIgAGAAQeAA==.Rainbow:BAABLgAECn8vAAIdAAkJWx/gCQD7AgAdAAkJWx/gCQD7AgABLgAECgkJOQAYAFQmAA==.Rastasham:BAAALgAECggJDgAAAA==.Ratfondler:BAACLgAFFH8IAAMcAAMJah53GAAAAQAcAAMJah53GAAAAQAdAAEJcwabawApAAAuAAQKfywAAxwACQlMI6wDACUDABwACQlMI6wDACUDAB0ABAlSD9dvAMgAAAAA.',
Re='Reialaleigh:BAAALgAECgUJDQAAAA==.',
Ri='Ricanthetank:BAAALgAECgQJBAAAAA==.',
Ry='Rysho:BAAALgAECgEJAQAAAA==.',
Sa='Sabeam:BAACLgAFFH8VAAITAAUJTBefCQCQAQATAAUJTBefCQCQAQAuAAQKfzAAAhMACQnwH84HAE0DABMACQnwH84HAE0DAAAA.Saberdiva:BAABLgAECn81AAIHAAgJlBERkQBQAQAHAAgJlBERkQBQAQAAAA==.Saberlorian:BAAALgADCgEJAQAAAA==.Sabershot:BAAALgADCgMJAwAAAA==.Sabersidious:BAAALgADCgUJBQAAAA==.Saberthyr:BAAALgADCgkJEQAAAA==.Saberwookie:BAAALgADCgUJBQAAAA==.Sabs:BAAALgAFFAIJAgABLgAFFAUJFQATAEwXAA==.Sagesteppe:BAABLgAECn8WAAILAAYJ9ghlIgDkAAALAAYJ9ghlIgDkAAAAAA==.Santhon:BAAALgAECgEJAwAAAA==.',
Sc='Scotticus:BAABLgAECn8jAAIEAAgJKg+KkgBBAQAEAAgJKg+KkgBBAQAAAA==.',
Se='Seditionist:BAABLgAECn8gAAIYAAgJIQXfVgDgAAAYAAgJIQXfVgDgAAAAAA==.Sellis:BAAALgADCgEJAQAAAA==.',
Sh='Shakira:BAAALgADCgkJCQABLgAECgUJDQAUAAAAAA==.Shammywow:BAAALgADCgEJAQAAAA==.Shamon:BAAALgAECgkJBQAAAA==.Shinju:BAAALgAECgEJAQAAAA==.Shåtheed:BAAALgADCgYJBgAAAA==.',
Si='Sidthekid:BAAALgAECgYJEgAAAA==.Sinayion:BAABLgAECn8nAAIVAAkJIwSTJgDhAAAVAAkJIwSTJgDhAAAAAA==.',
Sl='Sluggina:BAAALgAECgIJAwAAAA==.',
St='Stepbro:BAAALgAECgEJAQABLgAECggJGQAMAO4aAA==.Stepdemonh:BAAALgADCgkJEwAAAA==.Stepsis:BAAALgAFFAEJAQABLgAECggJGQAMAO4aAA==.Stinkoman:BAAALgAECgQJBwABLgAECgQJCAAUAAAAAA==.',
Su='Sunarena:BAABLgAECn8fAAIHAAkJJg8QiwBbAQAHAAkJJg8QiwBbAQAAAA==.',
Ta='Tankobell:BAABLgAECn8bAAIHAAkJBhHiWQC/AQAHAAkJBhHiWQC/AQAAAA==.Tavius:BAAALgADCgEJAQAAAA==.',
Te='Terrible:BAEALgAECgcJAgABLgAFFAcJHAAIAM8bAA==.',
Th='Thannatos:BAAALgAECgEJAQAAAA==.Thejuiciest:BAAALgADCgEJAgAAAA==.',
To='Tommet:BAAALgADCgUJBQAAAA==.Toukadh:BAAALgAECgYJAgAAAA==.',
Tr='Truart:BAAALgAECggJCQAAAA==.',
Tu='Tuerjoie:BAABLgAECn8mAAIBAAgJQhgMUgDmAQABAAgJQhgMUgDmAQAAAA==.',
Tw='Twíla:BAAALgADCgYJCwAAAA==.',
Ty='Tywin:BAAALgAECgMJAwAAAA==.',
Ug='Ugooboom:BAAALgAECgEJAQAAAA==.',
Uh='Uh:BAAALgADCgYJDAAAAA==.',
Un='Unclemagic:BAAALgAECgYJCwABLgAFFAYJCwAOADwNAA==.',
Ut='Utopia:BAAALgAECgQJAwAAAA==.',
Va='Valesko:BAAALgAFFAEJAQAAAA==.Varfus:BAACLgAFFH8nAAMZAAgJ6x9aAACNAgAZAAgJ6x9aAACNAgATAAIJahAaCwCSAAAuAAQKfzMAAhkACQlKJnIAAFwDABkACQlKJnIAAFwDAAAA.',
Ve='Velentre:BAAALgAECgcJCgAAAA==.',
Vi='Vichy:BAAALgAECgYJCQAAAA==.Vikstyn:BAAALgAECgEJBAAAAA==.',
Vu='Vulquin:BAAALgAECgUJBQAAAA==.',
We='Weather:BAAALgAECgYJCAAAAA==.',
Wi='Wigskid:BAAALgADCgEJAQAAAA==.Winney:BAACLgAFFH8GAAIHAAUJSxXVXwDwAAAHAAUJSxXVXwDwAAAuAAQKfykAAgcACQnbJFQGAD4DAAcACQnbJFQGAD4DAAAA.',
Wo='Wolfjob:BAAALgADCgUJBQAAAA==.Wouka:BAABLgAECn80AAQOAAkJuyUJBABQAwAOAAkJqSUJBABQAwAKAAYJqiPVAwBQAgANAAIJsiPkKwBnAAAAAA==.',
Wu='Wukong:BAAALgADCgMJAwAAAA==.',
Ya='Yarlyah:BAAALgADCgkJDgABLgAECgIJAgAUAAAAAA==.',
Yo='Yoyomba:BAAALgAECgUJBQABLgAECggJJQAcALgaAA==.',
Za='Zargonia:BAAALgAECgEJAQAAAA==.Zaria:BAAALgADCgUJBQAAAA==.',
Ze='Zendetra:BAAALgADCgUJBQABLgAECgYJEQAUAAAAAA==.Zeposo:BAABLgAECn8jAAMMAAgJuhx0DgCBAgAMAAgJuhx0DgCBAgAXAAEJyAQDlQAlAAABLgAECgkJVAAGAC8dAA==.Zeppo:BAAALgAECgUJDAABLgAECgkJVAAGAC8dAA==.Zeptide:BAABLgAECn9UAAMGAAkJLx1RDAD3AgAGAAkJLx1RDAD3AgAYAAgJ5xPJKACpAQAAAA==.Zervish:BAAALgAECgEJAQAAAA==.',
Zo='Zoli:BAABLgAECn8YAAIQAAgJ2R8oCwBtAgAQAAgJ2R8oCwBtAgAAAA==.',
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
