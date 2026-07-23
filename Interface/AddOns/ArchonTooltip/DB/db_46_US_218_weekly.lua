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

local lookup = {'DeathKnight-Frost','DeathKnight-Blood','Shaman-Enhancement','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Paladin-Holy','Priest-Holy','Monk-Mistweaver','Druid-Restoration','Druid-Balance','Paladin-Retribution','DemonHunter-Devourer','Druid-Guardian','Unknown-Unknown','Warrior-Protection','Priest-Shadow','Paladin-Protection','Warlock-Affliction','Hunter-Survival','Shaman-Elemental','Mage-Frost','Shaman-Restoration','Priest-Discipline','Evoker-Augmentation','Evoker-Preservation','Warrior-Arms','Warrior-Fury','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','Mage-Arcane','DemonHunter-Vengeance','Monk-Brewmaster','Rogue-Outlaw','Druid-Feral','Mage-Fire','Monk-Windwalker','DemonHunter-Havoc',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Absolver:BAAALgADCgYJCwAAAA==.',
Ad='Adabisi:BAAALgADCgQJCQAAAA==.Addu:BAAALgAECgUJBgAAAA==.Adiforis:BAABLgAECn8iAAMBAAkJPBEYDAC2AQABAAkJtxAYDAC2AQACAAUJawriPACdAAAAAA==.Adobo:BAACLgAFFH8NAAIDAAUJeQdzBAAVAQADAAUJeQdzBAAVAQAuAAQKfxUAAgMACQk+Ea4LAPkBAAMACQk+Ea4LAPkBAAAA.Adventures:BAAALgADCgIJAgAAAA==.',
Ae='Aeralina:BAABLgAECn8XAAIEAAgJpQmqFAAYAQAEAAgJpQmqFAAYAQAAAA==.Aerandir:BAABLgAECn8bAAMFAAYJewsfFgCbAAAFAAYJewsfFgCbAAAGAAEJAAAXeQAqAAABLgAECgkJIwAHACARAA==.Aerin:BAAALgAECgEJAQAAAA==.Aerwyn:BAAALgAECgYJBgAAAA==.',
Ah='Ahmyra:BAAALgAECgcJEwAAAA==.',
Al='Alessar:BAAALgAECgYJDAAAAA==.Allysson:BAABLgAECn84AAIBAAkJMRTLCQDmAQABAAkJMRTLCQDmAQAAAA==.Alrekur:BAAALgAECgIJAgAAAA==.Alyestra:BAABLgAECn8ZAAIIAAgJzBEaLgClAQAIAAgJzBEaLgClAQAAAA==.',
Am='Ambien:BAAALgAECgYJCwAAAA==.',
An='Anibundance:BAAALgAECgcJDAABLgAECgkJLQAJAJ0iAA==.Animyst:BAACLgAFFH8JAAIKAAQJ8hx6JgA6AQAKAAQJ8hx6JgA6AQAuAAQKf1cAAgoACQnnJVYAAMgDAAoACQnnJVYAAMgDAAEuAAQKCQktAAkAnSIA.Anipaltu:BAACLgAFFH8IAAIIAAQJsAw0KQDcAAAIAAQJsAw0KQDcAAAuAAQKfx4AAggACQm2HQcJAPoCAAgACQm2HQcJAPoCAAEuAAQKCQktAAkAnSIA.Aniron:BAABLgAECn8UAAIFAAYJchEjjQAgAQAFAAYJchEjjQAgAQABLgAECgkJLQAJAJ0iAA==.Anirot:BAABLgAECn8tAAIJAAkJnSKSBAA3AwAJAAkJnSKSBAA3AwAAAA==.Anithwip:BAAALgAECgYJBgABLgAECgkJLQAJAJ0iAA==.Antoni:BAAALgAECgEJAQAAAA==.',
Ap='Aphirym:BAAALgAECgIJAgAAAA==.',
Ar='Aranta:BAABLgAECn8aAAMLAAYJmQ4yYQASAQALAAYJmQ4yYQASAQAMAAYJ9AlKUQDJAAAAAA==.Arcanium:BAAALgAECgEJAgAAAA==.Arissarel:BAAALgAECgEJAQAAAA==.Arkadis:BAAALgAECgEJAQAAAA==.',
As='Astren:BAABLgAECn8YAAINAAcJDBUyCwB7AQANAAcJDBUyCwB7AQAAAA==.Asynsia:BAABLgAECn8vAAIOAAkJfiG1EAC8AgAOAAkJfiG1EAC8AgAAAA==.',
Av='Avamani:BAAALgADCgkJCQAAAA==.',
Az='Azulmoon:BAAALgAECgYJCwAAAA==.',
Ba='Balrogg:BAAALgADCgcJBwAAAA==.Bartholomew:BAACLgAFFH8GAAIKAAQJVRBjMwDgAAAKAAQJVRBjMwDgAAAuAAQKfzMAAgoACQl+HtoLANsCAAoACQl+HtoLANsCAAAA.Bartno:BAAALgAECgIJAQAAAA==.',
Be='Beefed:BAAALgADCgIJAgAAAA==.Beertje:BAABLgAFFH8GAAIPAAMJdgz7EACQAAAPAAMJdgz7EACQAAABLgAFFAIJAgAQAAAAAA==.Bellathrix:BAAALgAECgMJAwAAAA==.Bellemore:BAAALgAECgEJAQAAAA==.Bessie:BAAALgADCgIJAgAAAA==.',
Bi='Bienfaiseur:BAABLgAECn9BAAIJAAkJjCU1AQC2AwAJAAkJjCU1AQC2AwAAAA==.Bigdamhero:BAAALgAECgIJAgAAAA==.Bigtonka:BAAALgADCgYJBgAAAA==.',
Bl='Bladez:BAAALgAECgYJBwAAAA==.',
Bo='Boffadeez:BAAALgAECgcJDAAAAA==.Boombawks:BAAALgADCgUJBQABLgAECgEJAgAQAAAAAA==.Boryndin:BAABLgAECn8iAAIRAAkJohkuDgAJAgARAAkJohkuDgAJAgAAAA==.',
Br='Brad:BAAALgADCgIJAgAAAA==.Breadbringer:BAAALgADCgIJAgAAAA==.Breadburn:BAAALgADCggJCAAAAA==.Breezybb:BAACLgAFFH8NAAINAAUJaREeSAAcAQANAAUJaREeSAAcAQAuAAQKfz4AAg0ACQlhHCw6ADoCAA0ACQlhHCw6ADoCAAAA.Brewfist:BAAALgADCgUJCAAAAA==.Brutonmage:BAAALgAECgcJBwAAAA==.',
Bu='Bulgrim:BAAALgADCggJEQAAAA==.',
Ca='Camhawk:BAAALgADCgkJCQAAAA==.Catastrophe:BAAALgAECgcJBwABLgAFFAIJAwAQAAAAAA==.',
Ce='Cearylin:BAAALgAECggJDQAAAA==.Cering:BAAALgAECgYJBgAAAA==.',
Ch='Changsauce:BAAALgAECgYJDAAAAA==.Cherypoptart:BAACLgAFFH8IAAISAAMJGx4+CwAXAQASAAMJGx4+CwAXAQAuAAQKfyUAAhIACAmdI1UJALkCABIACAmdI1UJALkCAAAA.Chrismeister:BAABLgAECn8eAAQTAAYJERL6BgDPAAATAAUJvhL6BgDPAAAIAAEJygtHlAArAAANAAEJAABv2gEAAAAAAA==.',
Ci='Cing:BAAALgAECgEJAQAAAA==.',
Cl='Claymordon:BAAALgADCgYJBgAAAA==.Clothpally:BAAALgAFFAEJAQAAAA==.',
Co='Codah:BAABLgAECn8WAAINAAUJKwJsRQBFAAANAAUJKwJsRQBFAAAAAA==.Contradict:BAAALgAECgYJBwABLgAECgkJMgANAOwdAA==.Coomonka:BAAALgADCgcJCQAAAA==.Coraggioso:BAAALgADCgYJBgAAAA==.Corbenik:BAAALgAECgIJBgABLgAECgcJGAAFAPEHAA==.',
Cr='Creel:BAAALgADCgYJBgAAAA==.Crethasmus:BAAALgAECgYJCAAAAA==.Crettephal:BAEBLgAECn8bAAIUAAYJeRKdFgAUAQAUAAYJeRKdFgAUAQAAAA==.Crodo:BAAALgADCgYJBgAAAA==.Cruella:BAAALgAECgEJAQAAAA==.',
['Cä']='Cähira:BAAALgAECgYJCAAAAA==.',
Da='Daellan:BAAALgAECgUJCQAAAA==.Dainaira:BAABLgAECn8XAAISAAkJywghCwDYAAASAAkJywghCwDYAAAAAA==.Daisia:BAABLgAECn8gAAIVAAkJyAa2JQBvAQAVAAkJyAa2JQBvAQAAAA==.Dalarrong:BAAALgAECgQJBAAAAA==.Dapanda:BAAALgAECgcJBgAAAA==.Dapandaz:BAAALgAECgkJAQAAAA==.Dasteaire:BAAALgAECgMJBgAAAA==.Daul:BAAALgADCgQJAQAAAA==.',
De='Deathdealler:BAABLgAECn8VAAMHAAgJvgL9+QC0AAAHAAgJewL9+QC0AAACAAUJ+wGmUABSAAAAAA==.Deathstopper:BAAALgAECgYJBwABLgAFFAMJCAAIACsOAA==.Delti:BAAALgADCgEJAQABLgAECgkJHwAOAFcWAA==.Demonicadhd:BAAALgAECgYJEwAAAA==.Demonsmind:BAABLgAECn8ZAAMFAAgJphE8egBFAQAFAAcJwBA8egBFAQAGAAMJqhEuQQCwAAAAAA==.Derien:BAABLgAECn8vAAIRAAkJqRc4AgDJAQARAAkJqRc4AgDJAQAAAA==.Derienfu:BAAALgAECgYJBgAAAA==.Devour:BAAALgAFFAEJAQABLgAFFAIJAgAQAAAAAA==.Dezin:BAAALgAECgYJCAAAAA==.',
Di='Dinkeldorf:BAAALgAECgMJBAABLgAFFAIJAgAQAAAAAA==.',
Dk='Dkerien:BAAALgAECggJCAAAAA==.',
Do='Donkeyteeth:BAABLgAECn8kAAIWAAkJag/CLgCGAQAWAAkJag/CLgCGAQAAAA==.Downtownbuu:BAAALgADCgcJDAAAAA==.',
Dr='Dracarian:BAAALgADCgMJAwAAAA==.Dracorz:BAAALgAECgYJCwAAAA==.Draqula:BAAALgAECgkJAgAAAA==.Dru:BAAALgADCgcJBwAAAA==.Drusila:BAAALgAECgEJAQAAAA==.Drywater:BAABLgAECn88AAIXAAkJNBEdEQAsAQAXAAkJNBEdEQAsAQAAAA==.',
Du='Duck:BAAALgAECgQJBAABLgAFFAIJAgAQAAAAAA==.Dura:BAABLgAECn83AAIYAAkJnBY1BwCgAQAYAAkJnBY1BwCgAQAAAA==.',
El='Eldermoon:BAAALgAFFAIJAgAAAA==.Eldunari:BAAALgAECgQJBAAAAA==.Elfblood:BAABLgAECn9HAAIGAAkJcQxtDwBJAQAGAAkJcQxtDwBJAQAAAA==.Elite:BAAALgAECgEJAQAAAA==.Elvion:BAAALgAECgMJBQAAAA==.',
Em='Emollama:BAABLgAECn9EAAMHAAkJyg0EVwDAAQAHAAkJyg0EVwDAAQACAAEJJwJpTQAcAAAAAA==.',
En='Engine:BAAALgADCgQJBAAAAA==.',
Ep='Ephimyra:BAAALgAECgQJCAAAAA==.',
Er='Erazer:BAAALgADCgMJAwAAAA==.Erílana:BAAALgAECgYJCwAAAA==.',
Et='Etiimasi:BAAALgADCgYJBwAAAA==.Ettolrahc:BAAALgAECgUJBQAAAA==.',
Ex='Expartaku:BAAALgADCgEJAQAAAA==.',
Ez='Ezanot:BAAALgADCgYJBgAAAA==.',
['Eï']='Eïr:BAAALgAECgQJCAABLgAFFAIJAgAQAAAAAA==.',
Fa='Fabulosa:BAABLgAECn8tAAQSAAgJtAxBMgBSAQASAAgJtAxBMgBSAQAZAAYJ2wnjLwAhAQAJAAUJYAqwVgCBAAAAAA==.Faith:BAABLgAECn8iAAINAAkJwxq5dACEAQANAAkJwxq5dACEAQAAAA==.',
Fe='Femidan:BAAALgAECgEJAQABLgAECgEJAgAQAAAAAA==.',
Fi='Finiquito:BAAALgADCgMJAwAAAA==.Finite:BAAALgAECgYJBwABLgAECgkJMgANAOwdAA==.',
Fn='Fndruid:BAAALgAECgEJAQAAAA==.Fnmage:BAAALgAECgQJDAAAAA==.Fnshaman:BAAALgAECgYJDAAAAA==.',
Fo='Fourscore:BAAALgADCgMJAwAAAA==.',
Fr='Frieren:BAAALgAECgQJBQABLgAFFAYJIgAaAEYjAA==.',
Fu='Furnok:BAABLgAECn9BAAMWAAkJ3xZ9FwApAgAWAAkJ3xZ9FwApAgAYAAcJMw0KZgApAQAAAA==.Fuzzyshukk:BAAALgAECgcJDgAAAA==.',
Ga='Galethia:BAAALgADCgkJMQAAAA==.Garli:BAAALgADCgMJAwAAAA==.Garmjackyl:BAAALgAECgEJAQAAAA==.',
Ge='Gerkin:BAAALgADCgcJDwAAAA==.',
Gg='Ggcthulhu:BAAALgAECgMJBQABLgAFFAQJBwAbAJ8IAA==.',
Gh='Ghutz:BAACLgAFFH8bAAMcAAQJxwzRHgD8AAAcAAQJxwzRHgD8AAARAAQJ6gFREQCMAAAuAAQKfzwABBwACQm6F+cNAAsCABwACQm6F+cNAAsCAB0ABwmICzZIAIMBABEAAgnHB+0LAGEAAAAA.',
Gl='Glitterhoof:BAABLgAECn8gAAIIAAkJjxkzGABGAgAIAAkJjxkzGABGAgAAAA==.Glorblariirn:BAAALgADCgYJBgAAAA==.Glumshanks:BAAALgAECgMJAwAAAA==.',
Go='Goliath:BAAALgAECgUJCwAAAA==.Gonja:BAAALgADCgcJFQAAAA==.',
Gr='Grimbjorne:BAAALgADCgcJBwAAAA==.Grimmbeardd:BAAALgADCgYJCgAAAA==.',
Gu='Gumbercules:BAABLgAECn9HAAIbAAkJahOVDAAMAgAbAAkJahOVDAAMAgAAAA==.',
Ha='Hammie:BAAALgADCgkJCQAAAA==.',
He='Hearthglen:BAABLgAECn8hAAINAAkJOxNpXAC5AQANAAkJOxNpXAC5AQAAAA==.',
Ho='Hollet:BAABLgAECn8xAAIeAAgJrhHHCgCSAQAeAAgJrhHHCgCSAQAAAA==.Holyblasto:BAAALgADCgEJAQAAAA==.Holyshukk:BAACLgAFFH8TAAIIAAYJVByuCgALAgAIAAYJVByuCgALAgAuAAQKfycAAwgACQmRIqEFABIDAAgACQmRIqEFABIDAA0AAQlCBwSzASgAAAEuAAQKBwkOABAAAAAA.',
Hu='Huckk:BAAALgAECgUJBQAAAA==.',
Hy='Hylen:BAABLgAECn8YAAIUAAkJ7hWkDgBxAQAUAAkJ7hWkDgBxAQAAAA==.',
Ib='Ibrandul:BAABLgAECn87AAINAAgJ7xd+TADhAQANAAgJ7xd+TADhAQAAAA==.',
Ic='Icyveins:BAABLgAECn8UAAIXAAcJ8wEyDAGaAAAXAAcJ8wEyDAGaAAAAAA==.',
Ir='Iroha:BAAALgADCgQJBgAAAA==.Ironhuntress:BAABLgAECn8kAAIeAAkJThL7DQBdAQAeAAkJThL7DQBdAQAAAA==.',
It='Ithro:BAABLgAECn8oAAIfAAkJJxiGBQAeAgAfAAkJJxiGBQAeAgAAAA==.',
Iy='Iyachtu:BAAALgAECgkJEwAAAA==.',
Ja='Jaciel:BAAALgAECgcJBwAAAA==.Jarlo:BAABLgAECn9HAAIfAAkJ1xtfAwCAAgAfAAkJ1xtfAwCAAgAAAA==.',
Je='Jeffeory:BAAALgAECgIJAgABLgAECgkJFgAVAEEXAA==.Jefficiently:BAABLgAECn8WAAMVAAkJQRcFAgDEAQAVAAgJIBIFAgDEAQAeAAgJfBcVCgCeAQAAAA==.Jefriel:BAAALgAECgYJBgABLgAECgkJFgAVAEEXAA==.Jezzi:BAAALgAECgMJAwAAAA==.',
Jo='Jobu:BAAALgAECgEJAgAAAA==.Jormungandr:BAABLgAECn80AAMcAAkJFSJeBQC1AgAcAAkJ1CFeBQC1AgARAAcJDRuoEgDBAQAAAA==.',
Ju='Juandolf:BAAALgAECgUJBgAAAA==.Juanhunglow:BAAALgAECgMJBwAAAA==.Judgederien:BAAALgAECgIJAgAAAA==.Jularity:BAAALgADCgYJBgAAAA==.',
Ka='Kaeldric:BAABLgAECn81AAMHAAkJ5CLoAwBKAgAHAAkJ5CLoAwBKAgACAAEJ/w9VYQAnAAAAAA==.Kairilynn:BAAALgAECgMJAwAAAA==.Kaladïn:BAAALgAECgEJAQAAAA==.Kalemshai:BAAALgADCgcJCwAAAA==.Kalinea:BAABLgAECn9AAAIeAAgJ/RR1CwCFAQAeAAgJ/RR1CwCFAQAAAA==.Karyia:BAAALgAECgUJBQAAAA==.Kayvaan:BAAALgAECgYJBgAAAA==.Kazuha:BAAALgAECgYJDgAAAA==.',
Ke='Keegh:BAAALgAECgcJBwAAAA==.Kellerun:BAAALgAECgIJAgAAAA==.Keruptadin:BAAALgAECgUJBgAAAA==.Ketosis:BAAALgAECgIJAgAAAA==.Keynnes:BAAALgAECgQJBAAAAA==.',
Kh='Khedriss:BAAALgAECgQJBAABLgAECgkJIwAHACARAA==.',
Ki='Kintha:BAAALgAECgYJBgAAAA==.',
Ko='Kope:BAABLgAECn80AAMbAAkJthvoAAApAgAbAAkJthvoAAApAgAaAAEJuhHmFwA1AAAAAA==.',
Kr='Kreltor:BAABLgAECn8vAAIYAAkJoSIXAwBVAgAYAAkJoSIXAwBVAgAAAA==.Kryptikz:BAABLgAECn8VAAMCAAkJXAsSJgAjAQACAAkJnQkSJgAjAQAHAAQJVhA05QC1AAAAAA==.Krystoferson:BAABLgAECn8kAAIgAAgJJAO2OADuAAAgAAgJJAO2OADuAAAAAA==.',
Ky='Kyrinea:BAAALgAECgMJAwAAAA==.',
La='Lalatína:BAAALgAECgEJAQAAAA==.Largar:BAAALgADCgUJCAAAAA==.',
Le='Leerroyy:BAAALgADCgIJAgAAAA==.Leesoftpaw:BAAALgADCgYJAgABLgAECgEJAgAQAAAAAA==.Leianii:BAABLgAECn8YAAIVAAgJCwJTQgC6AAAVAAgJCwJTQgC6AAAAAA==.Lextali:BAAALgAECgQJBAAAAA==.',
Lh='Lhondar:BAAALgAECgYJDwAAAA==.',
Li='Liafail:BAABLgAECn8YAAIFAAcJ8QesgwBTAQAFAAcJ8QesgwBTAQAAAA==.Likkaru:BAAALgAECgIJAwAAAA==.Lillat:BAABLgAECn8XAAIJAAcJTg7PMgA+AQAJAAcJTg7PMgA+AQAAAA==.Lin:BAAALgAECgEJAQAAAA==.Liryv:BAAALgADCgYJFAAAAA==.Littlepop:BAAALgAECgUJBAAAAA==.',
Lo='Lollilock:BAAALgAECgcJBAAAAA==.',
Lu='Luena:BAAALgAECgYJEgAAAA==.Lugglugg:BAAALgAECgQJBAAAAA==.Lumbre:BAAALgADCgcJCQAAAA==.Luminara:BAAALgAECgcJDgAAAA==.Luuggork:BAAALgAECgMJCAAAAA==.',
Ly='Lyarith:BAAALgAECgMJAwAAAA==.Lyrà:BAAALgAECgQJAwAAAA==.',
['Lá']='Ládydèath:BAAALgAECgYJBwAAAA==.',
['Lì']='Lìesson:BAABLgAECn85AAINAAkJiCEQEQDeAgANAAkJiCEQEQDeAgAAAA==.',
Ma='Mabo:BAAALgAECgEJAQAAAA==.Mackaroni:BAACLgAFFH8HAAIXAAQJWhBpaAATAQAXAAQJWhBpaAATAQAuAAQKfx4AAxcACQndFyljALgBABcACAlSFiljALgBACEAAwk+FlEEAJUAAAEuAAUUAgkCABAAAAAA.Madolynne:BAAALgADCgIJAgAAAA==.Madrel:BAAALgADCgUJBQAAAA==.Magesca:BAABLgAECn9PAAIXAAkJkRs9KQB1AgAXAAkJkRs9KQB1AgAAAA==.Magimiester:BAAALgADCgEJAQABLgAECgYJHgATABESAA==.Mahalath:BAAALgADCgMJAwAAAA==.Makkagg:BAACLgAFFH8cAAMRAAUJrBtvEgAUAQARAAQJvRlvEgAUAQAdAAUJdQ+fFwDOAAAuAAQKfzsAAxEACQkiIUQFAMYCABEACQkiIUQFAMYCAB0ACAlWDMc5AL8BAAAA.Malamur:BAAALgADCggJEgAAAA==.Malisea:BAABLgAECn8lAAIXAAkJswhjeQCGAQAXAAkJswhjeQCGAQAAAA==.',
Me='Melarndra:BAAALgADCgYJBgAAAA==.Melynea:BAAALgADCgEJAQAAAA==.Merillion:BAAALgAECgYJBgAAAA==.',
Mi='Milagrosa:BAABLgAECn8lAAIaAAkJ6w5rLwB7AQAaAAkJ6w5rLwB7AQAAAA==.Mirael:BAACLgAFFH8UAAIeAAYJqRg4HwCHAQAeAAYJqRg4HwCHAQAuAAQKfzkAAh4ACQm7IcAIAAcDAB4ACQm7IcAIAAcDAAAA.Mishuntsalot:BAAALgAECgQJBQABLgAECgYJCAAQAAAAAA==.',
Mo='Molocherx:BAAALgADCgMJAwAAAA==.Mommacoo:BAABLgAECn8hAAINAAYJaAo22ADoAAANAAYJaAo22ADoAAAAAA==.Mori:BAAALgAECgEJAQAAAA==.',
Mu='Mumbletung:BAAALgAECgkJAQAAAA==.Mumsms:BAAALgAECgkJBgAAAA==.Mumsurprise:BAAALgAECgkJAgAAAA==.',
My='Myrmia:BAABLgAECn8aAAILAAcJvg1iWAAvAQALAAcJvg1iWAAvAQAAAA==.Mystfang:BAABLgAECn8cAAIXAAkJihQoTwDuAQAXAAkJihQoTwDuAQAAAA==.',
['Mà']='Màck:BAAALgAFFAIJAgAAAA==.',
Na='Nade:BAAALgAECgcJBAAAAA==.Nargul:BAABLgAECn8vAAIFAAcJbRv4QADZAQAFAAcJbRv4QADZAQAAAA==.Naturboom:BAAALgAECgEJAQAAAA==.',
Ne='Nekossian:BAAALgAECgYJCwABLgAECgkJFgAVAEEXAA==.',
Ni='Nickorvis:BAAALgADCgUJBQABLgAECgcJGAAFAPEHAA==.Nirazen:BAAALgAECgIJAwAAAA==.',
No='Noburin:BAAALgADCgQJBAAAAA==.Nonae:BAEALgADCgYJBgAAAA==.Nota:BAABLgAECn8gAAINAAkJswfpHwC0AAANAAkJswfpHwC0AAAAAA==.',
Oa='Oathmere:BAAALgAECgQJBQAAAA==.',
Og='Ogrusao:BAABLgAECn8nAAIeAAkJtw2BEQAyAQAeAAkJtw2BEQAyAQAAAA==.Ogun:BAAALgADCgcJCgAAAA==.',
Or='Orukai:BAAALgAECgIJAgAAAA==.',
Pa='Panasaurus:BAABLgAECn9HAAIiAAkJ0RVeCADuAQAiAAkJ0RVeCADuAQAAAA==.',
Pe='Pechuuga:BAABLgAECn8WAAIjAAcJwBmCMgCHAQAjAAcJwBmCMgCHAQAAAA==.Pelli:BAABLgAECn81AAISAAkJkwkHCAAZAQASAAkJkwkHCAAZAQAAAA==.Pendraig:BAAALgAECgYJDAAAAA==.Pestilense:BAAALgADCgIJAgAAAA==.',
Pl='Plaza:BAABLgAFFH8FAAIHAAMJoBLINgDsAAAHAAMJoBLINgDsAAAAAA==.',
Qi='Qishawi:BAAALgAECgEJAQAAAA==.',
Qu='Quadrilio:BAAALgADCgUJBQAAAA==.Quamutei:BAAALgADCgUJBgAAAA==.',
Ra='Raylisarri:BAAALgAECgYJCQAAAA==.Rayst:BAABLgAECn9BAAIXAAgJ/wV6HgC+AAAXAAgJ/wV6HgC+AAAAAA==.Razìel:BAAALgADCgMJAgAAAA==.',
Rh='Rhalek:BAACLgAFFH8GAAILAAMJhxL0QQCqAAALAAMJhxL0QQCqAAAuAAQKfzEAAgsACQm3IGABAL4CAAsACQm3IGABAL4CAAEuAAUUBAkTAAsAxxQA.Rheunae:BAAALgAECgQJBAAAAA==.Rhykis:BAABLgAECn8lAAMdAAkJMCOHCQDKAgAdAAkJiiKHCQDKAgARAAMJcBrIBQDpAAAAAA==.',
Ri='Rilis:BAAALgADCgEJAQAAAA==.Rillyn:BAABLgAECn86AAMVAAkJKhdEDwA5AgAVAAkJxhZEDwA5AgAeAAEJ+hRPJAE7AAAAAA==.',
Ro='Rojei:BAAALgADCgYJBgAAAA==.Role:BAAALgADCgEJAQABLgAECggJLgAkAGUZAA==.',
Ru='Rubbin:BAAALgAECgEJAQAAAA==.',
['Rã']='Rãyné:BAAALgAECgkJAQAAAA==.',
Sa='Sabba:BAAALgADCgYJBgAAAA==.Sagearian:BAAALgAECggJEgAAAA==.Salindill:BAAALgADCgMJAwAAAA==.Salline:BAABLgAECn81AAMeAAgJDA3PGQDlAAAeAAgJDA3PGQDlAAAVAAQJfALyVABaAAAAAA==.Samanda:BAABLgAECn8iAAIlAAcJ7RPUFQBrAQAlAAcJ7RPUFQBrAQAAAA==.Samshir:BAABLgAECn8jAAIHAAkJIBFcBwCqAQAHAAkJIBFcBwCqAQAAAA==.Sanzel:BAAALgAECgUJCQAAAA==.',
Sc='Scorned:BAABLgAECn8zAAIOAAgJBBMIUACVAQAOAAgJBBMIUACVAQAAAA==.Scratchddisc:BAAALgAECgEJAQABLgAECgEJAgAQAAAAAA==.',
Se='Sekrain:BAAALgAECgQJBAAAAA==.Seocharang:BAAALgAECgcJCwAAAA==.Seosinz:BAABLgAECn8cAAIMAAYJUhSzPAAeAQAMAAYJUhSzPAAeAQAAAA==.',
Sh='Shadowmane:BAAALgAECgEJAQAAAA==.Shamnasty:BAAALgAECgcJEwAAAA==.Shariaan:BAAALgAECgYJCQAAAA==.Shaylinn:BAAALgAECgMJCwAAAA==.Shenanigan:BAAALgADCgEJAQABLgAECgkJMgANAOwdAA==.Shiviya:BAAALgADCgMJAwAAAA==.Shukkle:BAAALgAECgQJBAABLgAECgcJDgAQAAAAAA==.Shukkvoker:BAAALgADCgQJBQABLgAECgcJDgAQAAAAAA==.Shùkkle:BAABLgAECn8WAAIMAAkJTx4fAQC+AgAMAAkJTx4fAQC+AgAAAA==.',
Si='Siella:BAABLgAECn83AAIJAAkJoBJ9IAC+AQAJAAkJoBJ9IAC+AQAAAA==.Sileves:BAAALgAECgEJAgABLgAECgYJCwAQAAAAAA==.Sinyas:BAAALgADCgYJBgAAAA==.Sitrom:BAAALgAECgUJCwAAAA==.',
Sn='Snayd:BAABLgAECn8yAAMXAAkJKCHiHwCfAgAXAAgJfiHiHwCfAgAmAAcJBxjLAABjAQAAAA==.Snowette:BAAALgADCgMJAwAAAA==.',
So='Solar:BAAALgAFFAIJAgAAAA==.Somenai:BAAALgAECgQJBQAAAA==.Sonofmums:BAAALgAECgkJDwAAAA==.Sora:BAAALgAECgEJAQAAAA==.Soulbaine:BAABLgAECn8aAAMCAAcJuBbsGgCGAQACAAcJuBbsGgCGAQAHAAQJRhLk8QC+AAAAAA==.',
Sp='Spazeric:BAABLgAECn8oAAQKAAkJzxRlHwAfAgAKAAkJzxRlHwAfAgAnAAcJKBawMwA1AQAjAAQJgQaOBwCjAAAAAA==.Spheria:BAABLgAECn8/AAIFAAkJAAnFagBnAQAFAAkJAAnFagBnAQAAAA==.',
St='Stalon:BAAALgADCgYJDgAAAA==.Stevyn:BAAALgAECgEJAQAAAA==.Strangeluve:BAAALgAECgcJEQAAAA==.',
Su='Suerte:BAAALgADCggJDQAAAA==.Sunadora:BAAALgADCgUJBQAAAA==.Suzieq:BAAALgADCgMJBgAAAA==.',
Sy='Sysnootles:BAAALgADCgYJBwAAAA==.',
['Sà']='Sàyori:BAAALgAECgUJBwAAAA==.',
Ta='Tabrett:BAAALgAECgIJAgAAAA==.Talashara:BAAALgADCgEJAQAAAA==.Talashea:BAAALgAECgEJBAAAAA==.Tankdezoe:BAAALgAECgMJBAABLgAECggJEwAQAAAAAA==.Tarall:BAAALgAECgEJAQAAAA==.Taveres:BAAALgADCgEJAQAAAA==.Tax:BAABLgAECn89AAIUAAgJJQkXBQDbAAAUAAgJJQkXBQDbAAAAAA==.',
Te='Tenara:BAAALgADCgkJEgAAAA==.Tequ:BAAALgAECgMJCwAAAA==.',
Ti='Tiche:BAABLgAECn8WAAIKAAcJ8BI3CACDAQAKAAcJ8BI3CACDAQABLgAFFAMJCAAIACsOAA==.Tim:BAABLgAFFH8GAAIYAAMJ0RbVSwDDAAAYAAMJ0RbVSwDDAAAAAA==.Timeshade:BAAALgAECgUJCgAAAA==.Timeshadow:BAABLgAECn8fAAMgAAYJoQO5QADCAAAgAAYJhwO5QADCAAAfAAEJxgOSCAAeAAAAAA==.Tinakoffee:BAAALgAECgIJAgAAAA==.Tine:BAABLgAECn8qAAIXAAkJ4xcsRQALAgAXAAkJ4xcsRQALAgAAAA==.',
To='Tope:BAAALgAECgYJCwAAAA==.Toray:BAABLgAECn8iAAINAAgJbBNnagCaAQANAAgJbBNnagCaAQAAAA==.',
Tr='Triplesix:BAABLgAECn8ZAAMoAAkJLBKrKAA3AQAoAAkJLBKrKAA3AQAOAAcJ8AS+sgDDAAAAAA==.Trittia:BAABLgAECn9MAAMdAAkJBhc6AgAmAgAdAAkJtxY6AgAmAgARAAUJfA6KBgDNAAAAAA==.',
Tu='Tukk:BAABLgAECn8VAAMRAAcJGxI3HwA5AQARAAcJ4hE3HwA5AQAcAAEJwArdgQAoAAAAAA==.Turtle:BAAALgAECgEJBQAAAA==.',
Tw='Twigatron:BAABLgAECn8VAAILAAgJCBUYLwDoAQALAAgJCBUYLwDoAQABLgAECgcJEQAQAAAAAA==.Twigdin:BAAALgADCgMJAwAAAA==.Twigdun:BAAALgAECgMJBgAAAA==.',
Ty='Tynk:BAAALgAECggJEQAAAA==.',
Ur='Urza:BAAALgAECgYJCgAAAA==.',
Va='Vaewind:BAAALgADCgMJAwAAAA==.Valethus:BAABLgAECn8+AAMeAAkJZSBJAgDUAgAeAAkJZSBJAgDUAgAEAAIJVAgefgBNAAAAAA==.Valmaru:BAAALgADCgkJCQAAAA==.',
Ve='Velleria:BAAALgAECgEJAQAAAA==.Vesp:BAAALgAECgQJBQAAAA==.Vexxa:BAABLgAECn8YAAIOAAkJPBgASwClAQAOAAkJPBgASwClAQAAAA==.',
Vi='Viridania:BAAALgAECgUJEAAAAA==.',
Vy='Vynd:BAAALgAECgMJBQABLgAECgYJBgAQAAAAAA==.',
Wa='Walkz:BAABLgAECn8VAAIRAAYJ/B2vAwBRAQARAAYJ/B2vAwBRAQABLgAECgkJFQACAFwLAA==.Warrockhealz:BAAALgADCgYJBgAAAA==.',
Wi='Wickedlight:BAABLgAECn9BAAISAAkJhCAJBgDyAgASAAkJhCAJBgDyAgAAAA==.Wickedlock:BAAALgAECgQJCQAAAA==.Wiggleston:BAACLgAFFH8IAAIIAAMJKw4AGACDAAAIAAMJKw4AGACDAAAuAAQKfywABAgACQluEmkgAAACAAgACQluEmkgAAACAA0AAwljA4tKAWMAABMAAQlkALkXAA4AAAAA.Willscarlet:BAABLgAECn8WAAIeAAcJFAVzpQD3AAAeAAcJFAVzpQD3AAAAAA==.',
Wo='Wollybully:BAAALgADCgQJCQABLgAECgYJHgATABESAA==.',
Wy='Wylder:BAABLgAECn8aAAIRAAcJDgeOLQDPAAARAAcJDgeOLQDPAAAAAA==.Wylethia:BAAALgAECgQJBAAAAA==.',
Xa='Xandris:BAAALgAECgEJAgABLgAECgkJIwAHACARAA==.',
Yf='Yffre:BAAALgAECgYJBgAAAA==.',
Yh='Yhana:BAAALgADCggJEwAAAA==.',
Yo='Yolifeismine:BAAALgAECgUJBQAAAA==.Yozsh:BAAALgAECgYJBgAAAA==.',
Za='Zanthiava:BAAALgAECgYJBwAAAA==.Zarathia:BAABLgAECn8ZAAIoAAcJfAqjMgD4AAAoAAcJfAqjMgD4AAAAAA==.Zargar:BAAALgAECgEJAQAAAA==.Zaritym:BAABLgAECn8jAAMKAAkJJho2HQAuAgAKAAkJJho2HQAuAgAnAAQJbw+7aACDAAAAAA==.Zarrilin:BAABLgAECn8oAAIXAAkJlBcpRQAMAgAXAAkJlBcpRQAMAgAAAA==.',
Ze='Zebop:BAAALgAECgEJAgAAAA==.Zeeley:BAAALgADCgYJCgAAAA==.Zelsada:BAAALgAECgEJAQAAAA==.',
Zi='Zibetha:BAACLgAFFH8WAAIGAAYJVBAXBAB2AQAGAAYJVBAXBAB2AQAuAAQKf1EAAgYACQnoHwoCAKoCAAYACQnoHwoCAKoCAAAA.',
Zo='Zoeheals:BAAALgAECggJEwAAAA==.',
Zu='Zuggtmoy:BAAALgADCgkJCgAAAA==.Zulmahn:BAABLgAECn8oAAMYAAkJ5xCzTQB6AQAYAAkJ5xCzTQB6AQAWAAgJYQPwbQCfAAAAAA==.',
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
