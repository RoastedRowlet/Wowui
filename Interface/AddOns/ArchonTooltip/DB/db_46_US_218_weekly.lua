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

local lookup = {'DeathKnight-Frost','DeathKnight-Blood','Shaman-Enhancement','Shaman-Restoration','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Paladin-Holy','Priest-Holy','Monk-Mistweaver','Druid-Restoration','Druid-Balance','Paladin-Retribution','DemonHunter-Devourer','Druid-Guardian','Unknown-Unknown','Warrior-Protection','Priest-Shadow','Paladin-Protection','Warlock-Affliction','Hunter-Survival','Shaman-Elemental','Mage-Frost','Hunter-BeastMastery','Priest-Discipline','Evoker-Augmentation','Evoker-Preservation','Warrior-Arms','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','Mage-Arcane','DemonHunter-Vengeance','Monk-Brewmaster','Rogue-Outlaw','Druid-Feral','Mage-Fire','Monk-Windwalker','DemonHunter-Havoc',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=46,date='2026-07-28',data={Ab='Absolver:BAAALgADCgYJCwAAAA==.',
Ad='Adabisi:BAAALgADCgQJCQAAAA==.Addu:BAAALgAECgUJBgAAAA==.Adiforis:BAABLgAECn8lAAMBAAkJjxMYDAC2AQABAAkJCxMYDAC2AQACAAYJpAviPACdAAAAAA==.Adobo:BAACLgAFFH8NAAIDAAUJeQc8BQAOAQADAAUJeQc8BQAOAQAuAAQKfx4AAwMACQk+Ea4LAPkBAAMACQk+Ea4LAPkBAAQABQmGEdoQAAQBAAAA.Adventures:BAAALgADCgIJAgAAAA==.',
Ae='Aeralina:BAABLgAECn8XAAIFAAgJpQmqFAAYAQAFAAgJpQmqFAAYAQAAAA==.Aerandir:BAABLgAECn8bAAMGAAYJewvkGACZAAAGAAYJewvkGACZAAAHAAEJAAAXeQAqAAABLgAECgkJIwAIACARAA==.Aerin:BAAALgAECgEJAQAAAA==.Aerwyn:BAAALgAECgYJBgAAAA==.',
Ah='Ahmyra:BAAALgAECgcJEwAAAA==.',
Al='Alessar:BAAALgAECgYJDAAAAA==.Allysson:BAABLgAECn84AAIBAAkJMRTLCQDmAQABAAkJMRTLCQDmAQAAAA==.Alrekur:BAAALgAECgIJAgAAAA==.Alyestra:BAABLgAECn8ZAAIJAAgJzBEaLgClAQAJAAgJzBEaLgClAQAAAA==.',
Am='Ambien:BAAALgAECgYJCwAAAA==.',
An='Anibundance:BAAALgAECgcJDAABLgAECgkJLQAKAJ0iAA==.Animyst:BAACLgAFFH8JAAILAAQJ8hx6JgA6AQALAAQJ8hx6JgA6AQAuAAQKf1cAAgsACQnnJWoAAMUDAAsACQnnJWoAAMUDAAEuAAQKCQktAAoAnSIA.Anipaltu:BAACLgAFFH8IAAIJAAQJsAw0KQDcAAAJAAQJsAw0KQDcAAAuAAQKfx4AAgkACQm2HQcJAPoCAAkACQm2HQcJAPoCAAEuAAQKCQktAAoAnSIA.Aniron:BAABLgAECn8UAAIGAAYJchEjjQAgAQAGAAYJchEjjQAgAQABLgAECgkJLQAKAJ0iAA==.Anirot:BAABLgAECn8tAAIKAAkJnSKSBAA3AwAKAAkJnSKSBAA3AwAAAA==.Anithwip:BAAALgAECgYJBgABLgAECgkJLQAKAJ0iAA==.Antoni:BAAALgAECgEJAQAAAA==.',
Ap='Aphirym:BAAALgAECgIJAgAAAA==.',
Ar='Aranta:BAABLgAECn8aAAMMAAYJmQ4yYQASAQAMAAYJmQ4yYQASAQANAAYJ9AlKUQDJAAAAAA==.Arcanium:BAAALgAECgEJAgAAAA==.Arissarel:BAAALgAECgEJAQAAAA==.Arkadis:BAAALgAECgEJAQAAAA==.',
As='Astren:BAABLgAECn8YAAIOAAcJDBX+DAB3AQAOAAcJDBX+DAB3AQAAAA==.Asynsia:BAABLgAECn8vAAIPAAkJfiG1EAC8AgAPAAkJfiG1EAC8AgAAAA==.',
Av='Avamani:BAAALgADCgkJCQAAAA==.',
Az='Azulmoon:BAAALgAECgYJCwAAAA==.',
Ba='Balrogg:BAAALgADCgcJBwAAAA==.Bartholomew:BAACLgAFFH8GAAILAAQJVRBjMwDgAAALAAQJVRBjMwDgAAAuAAQKfzMAAgsACQl+HtoLANsCAAsACQl+HtoLANsCAAAA.Bartno:BAAALgAECgIJAQAAAA==.',
Be='Beefed:BAAALgADCgIJAgAAAA==.Beertje:BAABLgAFFH8GAAIQAAMJdgy1EgCMAAAQAAMJdgy1EgCMAAABLgAFFAIJAgARAAAAAA==.Bellathrix:BAAALgAECgQJBAAAAA==.Bellemore:BAAALgAECgEJAQAAAA==.Bessie:BAAALgADCgIJAgAAAA==.',
Bi='Bienfaiseur:BAABLgAECn9BAAIKAAkJjCU1AQC2AwAKAAkJjCU1AQC2AwAAAA==.Bigdamhero:BAAALgAECgIJAwAAAA==.Bigtonka:BAAALgADCgYJBgAAAA==.',
Bl='Bladez:BAAALgAECgYJBwAAAA==.',
Bo='Boffadeez:BAAALgAECgcJDAAAAA==.Boombawks:BAAALgADCgUJBQABLgAECgEJAgARAAAAAA==.Boryndin:BAABLgAECn8iAAISAAkJohkuDgAJAgASAAkJohkuDgAJAgAAAA==.',
Br='Brad:BAAALgADCgIJAgAAAA==.Breadbringer:BAAALgADCgIJAgAAAA==.Breadburn:BAAALgADCggJCAAAAA==.Breezybb:BAACLgAFFH8NAAIOAAUJaREeSAAcAQAOAAUJaREeSAAcAQAuAAQKf0AAAg4ACQlaHSw6ADoCAA4ACQlaHSw6ADoCAAAA.Brewfist:BAAALgADCgUJCAAAAA==.Brutonmage:BAAALgAECgcJBwAAAA==.',
Bu='Bulgrim:BAAALgADCggJEQAAAA==.',
Ca='Camhawk:BAAALgADCgkJCQAAAA==.Catastrophe:BAAALgAECgcJBwABLgAFFAIJAwARAAAAAA==.',
Ce='Cearylin:BAAALgAECggJDQAAAA==.Cering:BAAALgAECgYJBgAAAA==.',
Ch='Changsauce:BAAALgAECgYJDAAAAA==.Cherypoptart:BAACLgAFFH8IAAITAAMJGx4YDQARAQATAAMJGx4YDQARAQAuAAQKfyUAAhMACAmdI1UJALkCABMACAmdI1UJALkCAAAA.Chrismeister:BAABLgAECn8gAAQUAAcJLxDeBgDtAAAUAAYJWRDeBgDtAAAJAAEJygtHlAArAAAOAAEJAABv2gEAAAAAAA==.',
Ci='Cing:BAAALgAECgEJAQAAAA==.',
Cl='Claymordon:BAAALgADCgYJBgAAAA==.Clothpally:BAAALgAFFAEJAQAAAA==.',
Co='Codah:BAABLgAECn8WAAIOAAUJKwIDUAA/AAAOAAUJKwIDUAA/AAAAAA==.Contradict:BAAALgAECgYJBwABLgAECgkJMgAOAOwdAA==.Coomonka:BAAALgADCgcJCQAAAA==.Coraggioso:BAAALgADCgYJBgAAAA==.Corbenik:BAAALgAECgIJBgABLgAECgcJGAAGAPEHAA==.',
Cr='Creel:BAAALgADCgYJBgAAAA==.Crethasmus:BAAALgAECgYJCAAAAA==.Crettephal:BAEBLgAECn8bAAIVAAYJeRKdFgAUAQAVAAYJeRKdFgAUAQAAAA==.Crodo:BAAALgADCgYJBgAAAA==.Cruella:BAAALgAECgEJAQAAAA==.',
['Cä']='Cähira:BAAALgAECgYJCAAAAA==.',
Da='Daellan:BAAALgAECgUJCQAAAA==.Dainaira:BAABLgAECn8XAAITAAkJywiADQDLAAATAAkJywiADQDLAAAAAA==.Daisia:BAABLgAECn8gAAIWAAkJyAa2JQBvAQAWAAkJyAa2JQBvAQAAAA==.Dalarrong:BAAALgAECgQJBAAAAA==.Dapanda:BAAALgAECgcJBgAAAA==.Dapandaz:BAAALgAECgkJBAAAAA==.Dasteaire:BAAALgAECgMJBgAAAA==.Daul:BAAALgAECgQJBAAAAA==.',
De='Deathdealler:BAABLgAECn8VAAMIAAgJvgL9+QC0AAAIAAgJewL9+QC0AAACAAUJ+wGmUABSAAAAAA==.Deathstopper:BAAALgAECgYJBwABLgAECggJHAALANESAA==.Delti:BAAALgADCgEJAQABLgAECgkJHwAPAFcWAA==.Demonicadhd:BAAALgAECgYJEwAAAA==.Demonsmind:BAABLgAECn8ZAAMGAAgJphE8egBFAQAGAAcJwBA8egBFAQAHAAMJqhEuQQCwAAAAAA==.Derien:BAABLgAECn8vAAISAAkJqReKAgDGAQASAAkJqReKAgDGAQAAAA==.Derienfu:BAAALgAECgYJBgAAAA==.Devlyn:BAAALgAECgQJBAAAAA==.Devour:BAAALgAFFAEJAQABLgAFFAIJAgARAAAAAA==.Dezin:BAAALgAECgYJCAAAAA==.',
Di='Dinkeldorf:BAAALgAECgMJBAABLgAFFAIJAgARAAAAAA==.',
Dk='Dkerien:BAAALgAECggJCAAAAA==.',
Do='Donkeyteeth:BAABLgAECn8kAAIXAAkJag/CLgCGAQAXAAkJag/CLgCGAQAAAA==.Downtownbuu:BAAALgAECgQJBAAAAA==.',
Dr='Dracarian:BAAALgADCgMJAwAAAA==.Dracorz:BAAALgAECgYJCwAAAA==.Draqula:BAAALgAECgkJAgAAAA==.Dru:BAAALgADCgcJBwAAAA==.Drusila:BAAALgAECgEJAQAAAA==.Drywater:BAABLgAECn88AAIYAAkJNBG+EwAoAQAYAAkJNBG+EwAoAQAAAA==.',
Du='Duck:BAAALgAECgQJBAABLgAFFAIJAgARAAAAAA==.Dura:BAABLgAECn83AAIEAAkJnBZ2CACdAQAEAAkJnBZ2CACdAQAAAA==.',
El='Eldermoon:BAAALgAFFAIJAgAAAA==.Eldunari:BAAALgAECgQJBAAAAA==.Elfblood:BAABLgAECn9HAAIHAAkJcQxtDwBJAQAHAAkJcQxtDwBJAQAAAA==.Elite:BAAALgAECgEJAQAAAA==.Elvion:BAAALgAECgMJBQAAAA==.',
Em='Emollama:BAABLgAECn9EAAMIAAkJyg0EVwDAAQAIAAkJyg0EVwDAAQACAAEJJwJpTQAcAAAAAA==.',
En='Engine:BAAALgADCgQJBAAAAA==.',
Ep='Ephimyra:BAAALgAECgQJCAAAAA==.',
Er='Erazer:BAAALgADCgMJAwAAAA==.Erílana:BAAALgAECgYJCwAAAA==.',
Et='Etiimasi:BAAALgADCgYJBwAAAA==.Ettolrahc:BAAALgAECgUJBQAAAA==.',
Ev='Evanniá:BAABLgAECn81AAMZAAgJDA1JHADiAAAZAAgJDA1JHADiAAAWAAQJfALyVABaAAAAAA==.',
Ex='Expartaku:BAAALgADCgEJAQAAAA==.',
Ez='Ezanot:BAAALgADCgYJBgAAAA==.',
['Eï']='Eïr:BAAALgAECgQJCAABLgAFFAIJAgARAAAAAA==.',
Fa='Fabulosa:BAABLgAECn8tAAQTAAgJtAxBMgBSAQATAAgJtAxBMgBSAQAaAAYJ2wnjLwAhAQAKAAUJYAqwVgCBAAAAAA==.Faith:BAABLgAECn8iAAIOAAkJwxq5dACEAQAOAAkJwxq5dACEAQAAAA==.',
Fe='Femidan:BAAALgAECgEJAQABLgAECgEJAgARAAAAAA==.',
Fi='Finiquito:BAAALgADCgMJAwAAAA==.Finite:BAAALgAECgYJBwABLgAECgkJMgAOAOwdAA==.',
Fn='Fndruid:BAAALgAECgEJAgAAAA==.Fnmage:BAAALgAECgQJEAAAAA==.Fnshaman:BAAALgAECgYJEgAAAA==.',
Fo='Fourscore:BAAALgADCgMJAwAAAA==.',
Fr='Frieren:BAAALgAECgQJBQABLgAFFAYJIgAbAEYjAA==.',
Fu='Furnok:BAABLgAECn9BAAMXAAkJ3xZ9FwApAgAXAAkJ3xZ9FwApAgAEAAcJMw0KZgApAQAAAA==.Fuzzyshukk:BAAALgAECgcJDgAAAA==.',
Ga='Galethia:BAAALgADCgkJMQAAAA==.Garli:BAAALgADCgMJAwAAAA==.Garmjackyl:BAAALgAECgEJAQAAAA==.',
Ge='Gerkin:BAAALgADCgcJDwAAAA==.',
Gg='Ggcthulhu:BAAALgAECgMJBQABLgAFFAQJBwAcAJ8IAA==.',
Gh='Ghutz:BAACLgAFFH8eAAMdAAQJxwzRHgD8AAAdAAQJxwzRHgD8AAASAAQJYAJtEgCMAAAuAAQKfzwABB0ACQm6F+cNAAsCAB0ACQm6F+cNAAsCAB4ABwmICzZIAIMBABIAAgnHBy0NAGEAAAAA.',
Gl='Glitterhoof:BAABLgAECn8gAAIJAAkJjxkzGABGAgAJAAkJjxkzGABGAgAAAA==.Glorblariirn:BAAALgADCgYJBgAAAA==.Glumshanks:BAAALgAECgMJAwAAAA==.',
Go='Goliath:BAAALgAECgUJCwAAAA==.Gonja:BAAALgADCgcJFQAAAA==.Gonzaga:BAAALgADCgUJBQAAAA==.',
Gr='Grimbjorne:BAAALgADCgcJBwAAAA==.Grimmbeardd:BAAALgADCgYJCgAAAA==.',
Gu='Gumbercules:BAABLgAECn9HAAIcAAkJahOVDAAMAgAcAAkJahOVDAAMAgAAAA==.',
Ha='Hammie:BAAALgADCgkJCQAAAA==.',
He='Hearthglen:BAABLgAECn8hAAIOAAkJOxNpXAC5AQAOAAkJOxNpXAC5AQAAAA==.',
Ho='Hollet:BAABLgAECn81AAIZAAkJLRP+CADNAQAZAAkJLRP+CADNAQAAAA==.Holyblasto:BAAALgADCgEJAQAAAA==.Holyshukk:BAACLgAFFH8TAAIJAAYJVByuCgALAgAJAAYJVByuCgALAgAuAAQKfycAAwkACQmRIqEFABIDAAkACQmRIqEFABIDAA4AAQlCBwSzASgAAAEuAAQKBwkOABEAAAAA.',
Hu='Huckk:BAAALgAECgUJBQAAAA==.',
Hy='Hylen:BAABLgAECn8YAAIVAAkJ7hWkDgBxAQAVAAkJ7hWkDgBxAQAAAA==.',
Ib='Ibrandul:BAABLgAECn87AAIOAAgJ7xd+TADhAQAOAAgJ7xd+TADhAQAAAA==.',
Ic='Icyveins:BAABLgAECn8UAAIYAAcJ8wEyDAGaAAAYAAcJ8wEyDAGaAAAAAA==.',
Ir='Iroha:BAAALgADCgQJBgAAAA==.Ironhuntress:BAABLgAECn8kAAIZAAkJThJqEQBEAQAZAAkJThJqEQBEAQAAAA==.',
It='Ithro:BAABLgAECn8oAAIfAAkJJxiGBQAeAgAfAAkJJxiGBQAeAgAAAA==.',
Iy='Iyachtu:BAAALgAECgkJEwAAAA==.',
Ja='Jaciel:BAAALgAECgcJBwAAAA==.Jarlo:BAABLgAECn9HAAIfAAkJ1xtfAwCAAgAfAAkJ1xtfAwCAAgAAAA==.',
Je='Jeffeory:BAAALgAECgIJAgABLgAECgkJFgAWAEEXAA==.Jefficiently:BAABLgAECn8WAAMWAAkJQRdjAgCxAQAWAAgJIBJjAgCxAQAZAAgJfBe/CwCTAQAAAA==.Jefriel:BAAALgAECgYJBgABLgAECgkJFgAWAEEXAA==.Jezzi:BAAALgAECgMJAwAAAA==.',
Jo='Jobu:BAAALgAECgEJAgAAAA==.Jormungandr:BAABLgAECn80AAMdAAkJFSJeBQC1AgAdAAkJ1CFeBQC1AgASAAcJDRuoEgDBAQAAAA==.',
Ju='Juandolf:BAAALgAECgUJBgAAAA==.Juanhunglow:BAAALgAECgMJBwAAAA==.Judgederien:BAAALgAECgIJAgAAAA==.Jularity:BAAALgADCgYJBgAAAA==.',
Ka='Kaeldric:BAABLgAECn81AAMIAAkJ5CJ1BABEAgAIAAkJ5CJ1BABEAgACAAEJ/w9VYQAnAAAAAA==.Kairilynn:BAAALgAECgMJAwAAAA==.Kaladïn:BAAALgAECgEJAQAAAA==.Kalemshai:BAAALgADCgcJCwAAAA==.Kalinea:BAABLgAECn9AAAIZAAgJ/RSWDQB3AQAZAAgJ/RSWDQB3AQAAAA==.Karyia:BAAALgAECgUJBQAAAA==.Kayvaan:BAAALgAECgYJBgAAAA==.Kazuha:BAAALgAECgYJDgAAAA==.',
Ke='Keegh:BAAALgAECgcJBwAAAA==.Kellerun:BAAALgAECgIJAgAAAA==.Keruptadin:BAAALgAECgUJBgAAAA==.Ketosis:BAAALgAECggJCQAAAA==.Keynnes:BAAALgAECgQJCAAAAA==.',
Kh='Khedriss:BAAALgAECgQJCAABLgAECgkJIwAIACARAA==.',
Ki='Kintha:BAAALgAECgYJBgAAAA==.',
Ko='Kope:BAABLgAECn80AAMcAAkJthsFAQArAgAcAAkJthsFAQArAgAbAAEJuhEQGgA0AAAAAA==.',
Kr='Kreltor:BAABLgAECn8vAAIEAAkJoSLjDQDnAgAEAAkJoSLjDQDnAgAAAA==.Kryptikz:BAABLgAECn8VAAMCAAkJXAsSJgAjAQACAAkJnQkSJgAjAQAIAAQJVhA05QC1AAAAAA==.Krystoferson:BAABLgAECn8oAAIgAAgJZgOzDQB8AAAgAAgJZgOzDQB8AAAAAA==.',
Ky='Kyrinea:BAAALgAECgMJAwAAAA==.',
La='Lalatína:BAAALgAECgEJAQAAAA==.Largar:BAAALgADCgUJCAAAAA==.',
Le='Leerroyy:BAAALgADCgIJAgAAAA==.Leesoftpaw:BAAALgADCgYJAgABLgAECgEJAgARAAAAAA==.Leianii:BAABLgAECn8YAAIWAAgJCwJTQgC6AAAWAAgJCwJTQgC6AAAAAA==.Lextali:BAAALgAECgQJBAAAAA==.',
Lh='Lhondar:BAAALgAECgYJDwAAAA==.',
Li='Liafail:BAABLgAECn8YAAIGAAcJ8QesgwBTAQAGAAcJ8QesgwBTAQAAAA==.Likkaru:BAAALgAECgIJAwAAAA==.Lillat:BAABLgAECn8XAAIKAAcJTg7PMgA+AQAKAAcJTg7PMgA+AQAAAA==.Lin:BAAALgAECgEJAQAAAA==.Liryv:BAAALgADCgYJFAAAAA==.Littlepop:BAAALgAECgUJBAAAAA==.',
Lo='Lollilock:BAAALgAECgcJBAAAAA==.',
Lu='Luena:BAAALgAECgYJEgAAAA==.Lugglugg:BAAALgAECgQJBAAAAA==.Lumbre:BAAALgADCgcJCQAAAA==.Luminara:BAAALgAECgcJDgAAAA==.Luuggork:BAAALgAECgMJCAAAAA==.',
Ly='Lyarith:BAAALgAECgMJAwAAAA==.Lyrà:BAAALgAECgQJAwAAAA==.',
['Lá']='Ládydèath:BAAALgAECgYJBwAAAA==.',
['Lä']='Lädygaga:BAAALgAECgEJAQAAAA==.',
['Lì']='Lìesson:BAABLgAECn85AAIOAAkJiCEQEQDeAgAOAAkJiCEQEQDeAgAAAA==.',
Ma='Mabo:BAAALgAECgEJAQAAAA==.Mackaroni:BAACLgAFFH8HAAIYAAQJWhBpaAATAQAYAAQJWhBpaAATAQAuAAQKfx4AAxgACQndFyljALgBABgACAlSFiljALgBACEAAwk+FncFAJkAAAEuAAUUAgkCABEAAAAA.Madolynne:BAAALgADCgIJAgAAAA==.Madrel:BAAALgADCgUJBQAAAA==.Magesca:BAABLgAECn9PAAIYAAkJkRs9KQB1AgAYAAkJkRs9KQB1AgAAAA==.Magimiester:BAAALgADCgEJAQABLgAECgcJIAAUAC8QAA==.Mahalath:BAAALgADCgMJAwAAAA==.Mahng:BAAALgADCgMJAwAAAA==.Makkagg:BAACLgAFFH8cAAMSAAUJrBtvEgAUAQASAAQJvRlvEgAUAQAeAAUJdQ8rGgDJAAAuAAQKfzsAAxIACQkiIUQFAMYCABIACQkiIUQFAMYCAB4ACAlWDMc5AL8BAAAA.Malamur:BAAALgADCggJEgAAAA==.Malisea:BAABLgAECn8lAAIYAAkJswhjeQCGAQAYAAkJswhjeQCGAQAAAA==.Malistrace:BAAALgADCgEJAQAAAA==.',
Me='Melarndra:BAAALgADCgYJBgAAAA==.Melynea:BAAALgADCgEJAQAAAA==.Merillion:BAAALgAECgYJBgAAAA==.',
Mi='Milagrosa:BAABLgAECn8lAAIbAAkJ6w5rLwB7AQAbAAkJ6w5rLwB7AQAAAA==.Mirael:BAACLgAFFH8UAAIZAAYJqRg4HwCHAQAZAAYJqRg4HwCHAQAuAAQKfzkAAhkACQm7IcAIAAcDABkACQm7IcAIAAcDAAAA.Mishuntsalot:BAAALgAECgQJBQABLgAECgYJCAARAAAAAA==.',
Mo='Molocherx:BAAALgADCgMJAwAAAA==.Mommacoo:BAABLgAECn8hAAIOAAYJaAo22ADoAAAOAAYJaAo22ADoAAAAAA==.Mori:BAAALgAECgEJAQAAAA==.',
Mu='Mumbletung:BAAALgAECgkJAQAAAA==.Mumsurprise:BAAALgAECgkJAgAAAA==.',
My='Myrmia:BAABLgAECn8aAAIMAAcJvg1iWAAvAQAMAAcJvg1iWAAvAQAAAA==.Mystfang:BAABLgAECn8cAAIYAAkJihQoTwDuAQAYAAkJihQoTwDuAQAAAA==.',
['Mà']='Màck:BAAALgAFFAIJAgAAAA==.',
Na='Nade:BAAALgAECgcJBAAAAA==.Nargul:BAABLgAECn8vAAIGAAcJbRv4QADZAQAGAAcJbRv4QADZAQAAAA==.Naturboom:BAAALgAECgEJAQAAAA==.',
Ne='Nekossian:BAAALgAECgYJCwABLgAECgkJFgAWAEEXAA==.',
Ni='Nickorvis:BAAALgADCgUJBQABLgAECgcJGAAGAPEHAA==.Nirazen:BAAALgAECgIJBAAAAA==.',
No='Noburin:BAAALgADCgQJBAAAAA==.Nonae:BAEALgADCgYJBgAAAA==.Nota:BAABLgAECn8gAAIOAAkJswc1JQCrAAAOAAkJswc1JQCrAAAAAA==.',
Oa='Oathmere:BAAALgAECgQJBQAAAA==.',
Og='Ogrusao:BAABLgAECn8nAAIZAAkJtw01FQAfAQAZAAkJtw01FQAfAQAAAA==.Ogun:BAAALgADCgcJCgAAAA==.',
Or='Orukai:BAAALgAECgIJAgAAAA==.',
Pa='Panasaurus:BAABLgAECn9HAAIiAAkJ0RVeCADuAQAiAAkJ0RVeCADuAQAAAA==.',
Pe='Pechuuga:BAABLgAECn8WAAIjAAcJwBmCMgCHAQAjAAcJwBmCMgCHAQAAAA==.Pelli:BAABLgAECn81AAITAAkJkwm9CQAKAQATAAkJkwm9CQAKAQAAAA==.Pendraig:BAAALgAECgYJDAAAAA==.Pestilense:BAAALgADCgIJAgAAAA==.',
Pl='Plaza:BAABLgAFFH8JAAIIAAMJoBIEPQDeAAAIAAMJoBIEPQDeAAAAAA==.',
Qi='Qishawi:BAAALgAECgEJAQAAAA==.',
Qu='Quadrilio:BAAALgADCgUJBQAAAA==.Quamutei:BAAALgADCgUJBgAAAA==.',
Ra='Raylisarri:BAAALgAECgYJCQAAAA==.Rayst:BAABLgAECn9BAAIYAAgJ/wVCIwC4AAAYAAgJ/wVCIwC4AAAAAA==.Razìel:BAAALgADCgMJAgAAAA==.',
Rh='Rhalek:BAACLgAFFH8HAAIMAAQJaxH0QQCqAAAMAAQJaxH0QQCqAAAuAAQKfzEAAgwACQm3IIQBAMACAAwACQm3IIQBAMACAAAA.Rheunae:BAAALgAECgQJBAAAAA==.Rhykis:BAABLgAECn8lAAMeAAkJMCOHCQDKAgAeAAkJiiKHCQDKAgASAAMJcBqRBgDmAAAAAA==.',
Ri='Rilis:BAAALgADCgEJAQAAAA==.Rillyn:BAABLgAECn86AAMWAAkJKhdEDwA5AgAWAAkJxhZEDwA5AgAZAAEJ+hRPJAE7AAAAAA==.',
Ro='Rojei:BAAALgADCgYJBgAAAA==.Role:BAAALgADCgEJAQABLgAECggJLgAkAGUZAA==.',
Ru='Rubbin:BAAALgAECgEJAQAAAA==.',
['Rã']='Rãyné:BAAALgAECgkJAQAAAA==.',
Sa='Sabba:BAAALgADCgYJBgAAAA==.Sagearian:BAAALgAECggJEgAAAA==.Salindill:BAAALgADCgMJAwAAAA==.Samanda:BAABLgAECn8iAAIlAAcJ7RPUFQBrAQAlAAcJ7RPUFQBrAQAAAA==.Samshir:BAABLgAECn8jAAIIAAkJIBFiCACnAQAIAAkJIBFiCACnAQAAAA==.Sanzel:BAAALgAECgUJCQAAAA==.',
Sc='Scorned:BAABLgAECn8zAAIPAAgJBBMIUACVAQAPAAgJBBMIUACVAQAAAA==.Scratchddisc:BAAALgAECgEJAQABLgAECgEJAgARAAAAAA==.',
Se='Sekrain:BAAALgAECgQJBAAAAA==.Seocharang:BAAALgAECgcJCwAAAA==.Seosinz:BAABLgAECn8cAAINAAYJUhSzPAAeAQANAAYJUhSzPAAeAQAAAA==.',
Sh='Shadowmane:BAAALgAECgEJAQAAAA==.Shamnasty:BAAALgAECgcJEwAAAA==.Shariaan:BAAALgAECgYJCQAAAA==.Shaylinn:BAAALgAECgQJDwAAAA==.Shenanigan:BAAALgADCgEJAQABLgAECgkJMgAOAOwdAA==.Shiviya:BAAALgADCgMJAwAAAA==.Shukkle:BAAALgAECgQJBAABLgAECgcJDgARAAAAAA==.Shukkvoker:BAAALgADCgQJBQABLgAECgcJDgARAAAAAA==.Shùkkle:BAABLgAECn8WAAINAAkJTx5SAQC2AgANAAkJTx5SAQC2AgAAAA==.',
Si='Siella:BAABLgAECn83AAIKAAkJoBJ9IAC+AQAKAAkJoBJ9IAC+AQAAAA==.Sileves:BAAALgAECgEJAgABLgAECgYJCwARAAAAAA==.Sinyas:BAAALgADCgYJBgAAAA==.Sitrom:BAAALgAECgUJCwAAAA==.',
Sn='Snayd:BAABLgAECn8yAAMYAAkJKCHiHwCfAgAYAAgJfiHiHwCfAgAmAAcJBxj5AABlAQAAAA==.Snowette:BAAALgADCgMJAwAAAA==.',
So='Solar:BAAALgAFFAIJAgAAAA==.Somenai:BAAALgAECgQJBQAAAA==.Sonofmums:BAAALgAECgkJEAAAAA==.Sora:BAAALgAECgEJAQAAAA==.Soulbaine:BAABLgAECn8aAAMCAAcJuBbsGgCGAQACAAcJuBbsGgCGAQAIAAQJRhLk8QC+AAAAAA==.',
Sp='Spazeric:BAABLgAECn8oAAQLAAkJzxRlHwAfAgALAAkJzxRlHwAfAgAnAAcJKBawMwA1AQAjAAQJgQaSCACaAAAAAA==.Spheria:BAABLgAECn8/AAIGAAkJAAnFagBnAQAGAAkJAAnFagBnAQAAAA==.',
St='Stalon:BAAALgADCgYJDgAAAA==.Stevyn:BAAALgAECgEJAQAAAA==.Strangeluve:BAAALgAECgcJEQAAAA==.',
Su='Suerte:BAAALgADCggJDQAAAA==.Sunadora:BAAALgADCgUJBQAAAA==.Suzieq:BAAALgADCgMJBgAAAA==.',
Sy='Sysnootles:BAAALgADCgYJBwAAAA==.',
['Sà']='Sàyori:BAAALgAECgUJBwAAAA==.',
Ta='Tabrett:BAAALgAECgIJAgAAAA==.Talashara:BAAALgADCgEJAQAAAA==.Talashea:BAAALgAECgEJBAAAAA==.Tankdezoe:BAAALgAECgMJBAABLgAECggJEwARAAAAAA==.Tarall:BAAALgAECgEJAQAAAA==.Taveres:BAAALgADCgEJAQAAAA==.Tax:BAABLgAECn89AAIVAAgJJQnwFQAbAQAVAAgJJQnwFQAbAQAAAA==.',
Te='Tenara:BAAALgADCgkJEgAAAA==.Tequ:BAAALgAECgQJDwAAAA==.',
Ti='Tiche:BAABLgAECn8cAAILAAgJ0RKSBgC/AQALAAgJ0RKSBgC/AQAAAA==.Tim:BAABLgAFFH8GAAIEAAMJ0RbVSwDDAAAEAAMJ0RbVSwDDAAAAAA==.Timeshade:BAAALgAECgUJCgAAAA==.Timeshadow:BAABLgAECn8fAAMgAAYJoQO5QADCAAAgAAYJhwO5QADCAAAfAAEJxgOiCQAeAAAAAA==.Tinakoffee:BAAALgAECgIJAgAAAA==.Tine:BAABLgAECn8qAAIYAAkJ4xcsRQALAgAYAAkJ4xcsRQALAgAAAA==.',
To='Tope:BAAALgAECgYJCwAAAA==.Toray:BAABLgAECn8iAAIOAAgJbBNnagCaAQAOAAgJbBNnagCaAQAAAA==.',
Tr='Triplesix:BAABLgAECn8ZAAMoAAkJLBKrKAA3AQAoAAkJLBKrKAA3AQAPAAcJ8AS+sgDDAAAAAA==.Trittia:BAABLgAECn9MAAMeAAkJBhebAgAmAgAeAAkJtxabAgAmAgASAAUJfA5qBwDKAAAAAA==.',
Tu='Tukk:BAABLgAECn8VAAMSAAcJGxI3HwA5AQASAAcJ4hE3HwA5AQAdAAEJwArdgQAoAAAAAA==.Turtle:BAAALgAECgEJBQAAAA==.',
Tw='Twigatron:BAABLgAECn8VAAIMAAgJCBUYLwDoAQAMAAgJCBUYLwDoAQABLgAECgcJEQARAAAAAA==.Twigdin:BAAALgADCgMJAwAAAA==.Twigdun:BAAALgAECgMJBgAAAA==.',
Ty='Tynk:BAAALgAECggJEQAAAA==.',
Ur='Urza:BAAALgAECgYJCgAAAA==.',
Va='Vaewind:BAAALgADCgMJAwAAAA==.Valethus:BAABLgAECn8+AAMZAAkJZSCwAgDIAgAZAAkJZSCwAgDIAgAFAAIJVAgefgBNAAAAAA==.Valmaru:BAAALgADCgkJCQAAAA==.',
Ve='Velleria:BAAALgAECgEJAQAAAA==.Verlis:BAAALgADCgIJAgAAAA==.Vesp:BAAALgAECgQJBQAAAA==.Vexxa:BAABLgAECn8YAAIPAAkJPBgASwClAQAPAAkJPBgASwClAQAAAA==.',
Vi='Viridania:BAAALgAECgUJEAAAAA==.',
Vy='Vynd:BAAALgAECgMJBQABLgAECgkJDwARAAAAAA==.',
Wa='Walkz:BAABLgAECn8VAAISAAYJ/B1BBABLAQASAAYJ/B1BBABLAQABLgAECgkJFQACAFwLAA==.Warrockhealz:BAAALgADCgYJBgAAAA==.',
Wi='Wickedlight:BAABLgAECn9BAAITAAkJhCAJBgDyAgATAAkJhCAJBgDyAgAAAA==.Wickedlock:BAAALgAECgQJCQAAAA==.Wiggleston:BAACLgAFFH8IAAIJAAMJKw4TGgB6AAAJAAMJKw4TGgB6AAAuAAQKfywABAkACQluEmkgAAACAAkACQluEmkgAAACAA4AAwljA4tKAWMAABQAAQlkADMbAA4AAAEuAAQKCAkcAAsA0RIA.Willscarlet:BAABLgAECn8WAAIZAAcJFAVzpQD3AAAZAAcJFAVzpQD3AAAAAA==.',
Wo='Wollybully:BAAALgADCgQJCQABLgAECgcJIAAUAC8QAA==.',
Wy='Wylder:BAABLgAECn8aAAISAAcJDgeOLQDPAAASAAcJDgeOLQDPAAAAAA==.Wylethia:BAAALgAECgQJBAAAAA==.',
Xa='Xandris:BAAALgAECgEJAgABLgAECgkJIwAIACARAA==.',
Yf='Yffre:BAAALgAECgYJBgAAAA==.',
Yh='Yhana:BAAALgADCggJEwAAAA==.',
Yo='Yolifeismine:BAAALgAECgUJBQAAAA==.Yozsh:BAAALgAECgYJBgAAAA==.',
Za='Zanthiava:BAAALgAECgYJBwAAAA==.Zarathia:BAABLgAECn8ZAAIoAAcJfAqjMgD4AAAoAAcJfAqjMgD4AAAAAA==.Zargar:BAAALgAECgEJAQAAAA==.Zaritym:BAABLgAECn8jAAMLAAkJJho2HQAuAgALAAkJJho2HQAuAgAnAAQJbw+7aACDAAAAAA==.Zarrilin:BAABLgAECn8oAAIYAAkJlBcpRQAMAgAYAAkJlBcpRQAMAgAAAA==.',
Ze='Zebop:BAAALgAECgEJAgAAAA==.Zeeley:BAAALgADCgYJCgAAAA==.Zelsada:BAAALgAECgEJAQAAAA==.',
Zi='Zibetha:BAACLgAFFH8WAAIHAAYJVBAXBAB2AQAHAAYJVBAXBAB2AQAuAAQKf1EAAgcACQnoHwoCAKoCAAcACQnoHwoCAKoCAAAA.',
Zo='Zoeheals:BAAALgAECggJEwAAAA==.',
Zu='Zuggtmoy:BAAALgADCgkJCgAAAA==.Zulmahn:BAABLgAECn8oAAMEAAkJ5xCzTQB6AQAEAAkJ5xCzTQB6AQAXAAgJYQPwbQCfAAAAAA==.',
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
