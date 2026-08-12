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

local lookup = {'DeathKnight-Frost','DeathKnight-Blood','Shaman-Enhancement','Shaman-Restoration','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Paladin-Holy','Priest-Holy','Monk-Mistweaver','Druid-Restoration','Druid-Balance','Paladin-Retribution','DemonHunter-Devourer','Unknown-Unknown','Druid-Guardian','Warrior-Protection','Priest-Shadow','Paladin-Protection','Warlock-Affliction','Hunter-Survival','Shaman-Elemental','Mage-Frost','Hunter-BeastMastery','Priest-Discipline','Evoker-Augmentation','Evoker-Preservation','Warrior-Arms','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','Mage-Arcane','DemonHunter-Vengeance','Monk-Brewmaster','Rogue-Outlaw','Druid-Feral','Mage-Fire','Monk-Windwalker','DemonHunter-Havoc',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=46,date='2026-08-11',data={Ab='Absolver:BAAALgADCgYJCwAAAA==.',
Ad='Adabisi:BAAALgADCgQJCQAAAA==.Addu:BAAALgAECgUJBgAAAA==.Adiforis:BAABLgAECn8sAAMBAAkJDBtTAQBgAgABAAkJDBtTAQBgAgACAAYJpAviPACdAAAAAA==.Adobo:BAACLgAFFH8NAAIDAAUJeQcABgAKAQADAAUJeQcABgAKAQAuAAQKfx4AAwMACQk+Ea4LAPkBAAMACQk+Ea4LAPkBAAQABQmGEXUTAAQBAAAA.Adventures:BAAALgADCgIJAgAAAA==.',
Ae='Aeralina:BAABLgAECn8XAAIFAAgJpQmqFAAYAQAFAAgJpQmqFAAYAQAAAA==.Aerandir:BAABLgAECn8bAAMGAAYJewtsHACVAAAGAAYJewtsHACVAAAHAAEJAAAXeQAqAAABLgAECgkJIwAIACARAA==.Aerin:BAAALgAECgEJAQAAAA==.Aerwyn:BAAALgAECgYJBgAAAA==.',
Ah='Ahmyra:BAAALgAECgcJEwAAAA==.',
Al='Alessar:BAAALgAECgYJDAAAAA==.Allysson:BAABLgAECn84AAIBAAkJMRTLCQDmAQABAAkJMRTLCQDmAQAAAA==.Alrekur:BAAALgAECgIJAgAAAA==.Alyestra:BAABLgAECn8ZAAIJAAgJzBEaLgClAQAJAAgJzBEaLgClAQAAAA==.',
Am='Amberwynd:BAAALgADCgEJAQAAAA==.Ambien:BAAALgAECgYJCwAAAA==.',
An='Anibundance:BAAALgAECgcJDAABLgAECgkJLQAKAJ0iAA==.Animyst:BAACLgAFFH8JAAILAAQJ8hx6JgA6AQALAAQJ8hx6JgA6AQAuAAQKf1cAAgsACQnnJX0AAMEDAAsACQnnJX0AAMEDAAEuAAQKCQktAAoAnSIA.Anipaltu:BAACLgAFFH8IAAIJAAQJsAw0KQDcAAAJAAQJsAw0KQDcAAAuAAQKfx4AAgkACQm2HQcJAPoCAAkACQm2HQcJAPoCAAEuAAQKCQktAAoAnSIA.Aniron:BAABLgAECn8UAAIGAAYJchEjjQAgAQAGAAYJchEjjQAgAQABLgAECgkJLQAKAJ0iAA==.Anirot:BAABLgAECn8tAAIKAAkJnSKSBAA3AwAKAAkJnSKSBAA3AwAAAA==.Anithwip:BAAALgAECgYJBgABLgAECgkJLQAKAJ0iAA==.Antoni:BAAALgAECgEJAQAAAA==.',
Ap='Aphirym:BAAALgAECgIJAgAAAA==.',
Ar='Aranta:BAABLgAECn8aAAMMAAYJmQ4yYQASAQAMAAYJmQ4yYQASAQANAAYJ9AlKUQDJAAAAAA==.Arcanium:BAAALgAECgEJAgAAAA==.Arissarel:BAAALgAECgEJAQAAAA==.Arkadis:BAAALgAECgEJAQAAAA==.',
As='Astren:BAABLgAECn8ZAAIOAAcJjhXSDgB8AQAOAAcJjhXSDgB8AQAAAA==.Asynsia:BAABLgAECn8vAAIPAAkJfiG1EAC8AgAPAAkJfiG1EAC8AgAAAA==.',
Av='Avamani:BAAALgADCgkJCQAAAA==.',
Az='Azulmoon:BAAALgAECgYJCwAAAA==.',
Ba='Balrogg:BAAALgADCgcJBwAAAA==.Bartholomew:BAACLgAFFH8IAAILAAQJJBFjMwDgAAALAAQJJBFjMwDgAAAuAAQKfzMAAgsACQl+HtoLANsCAAsACQl+HtoLANsCAAAA.Bartno:BAAALgAECgIJAQAAAA==.',
Be='Beauty:BAAALgAECgEJAgABLgAECgEJAgAQAAAAAA==.Beefed:BAAALgADCgIJAgAAAA==.Beertje:BAABLgAFFH8GAAIRAAMJdgxZFACFAAARAAMJdgxZFACFAAABLgAFFAIJAgAQAAAAAA==.Bellathrix:BAAALgAECgQJBAAAAA==.Bellemore:BAAALgAECgEJAQAAAA==.Bessie:BAAALgADCgIJAgAAAA==.',
Bi='Bienfaiseur:BAABLgAECn9BAAIKAAkJjCU1AQC2AwAKAAkJjCU1AQC2AwAAAA==.Bigdamhero:BAAALgAECgIJBAAAAA==.Bigtonka:BAAALgADCgYJBgAAAA==.',
Bl='Bladez:BAAALgAECgYJBwAAAA==.',
Bo='Boffadeez:BAAALgAECgcJDAAAAA==.Boombawks:BAAALgADCgUJBQABLgAECgEJAgAQAAAAAA==.Boryndin:BAABLgAECn8iAAISAAkJohkuDgAJAgASAAkJohkuDgAJAgAAAA==.',
Br='Brad:BAAALgADCgIJAgAAAA==.Breadbringer:BAAALgADCgIJAgAAAA==.Breadburn:BAAALgADCggJCAAAAA==.Breezybb:BAACLgAFFH8NAAIOAAUJaREeSAAcAQAOAAUJaREeSAAcAQAuAAQKf0AAAg4ACQlaHSw6ADoCAA4ACQlaHSw6ADoCAAAA.Brewfist:BAAALgADCgUJCAAAAA==.Brutonmage:BAAALgAECgcJBwAAAA==.',
Bu='Bulgrim:BAAALgADCggJEQAAAA==.',
Ca='Calluna:BAAALgADCgEJAQAAAA==.Camhawk:BAAALgADCgkJCQAAAA==.Catastrophe:BAAALgAECgcJBwABLgAFFAIJAwAQAAAAAA==.',
Ce='Cearylin:BAAALgAECgkJEwAAAA==.Cering:BAAALgAECgYJBgAAAA==.',
Ch='Changsauce:BAAALgAECgYJDAAAAA==.Cherypoptart:BAACLgAFFH8IAAITAAMJGx5pDgAKAQATAAMJGx5pDgAKAQAuAAQKfykAAhMACAmdI1UJALkCABMACAmdI1UJALkCAAAA.Chohha:BAAALgAECgIJAgAAAA==.Chrismeister:BAABLgAECn8gAAQUAAcJLxAaCADqAAAUAAYJWRAaCADqAAAJAAEJygtHlAArAAAOAAEJAABv2gEAAAAAAA==.',
Ci='Cing:BAAALgAECgEJAQAAAA==.Citrate:BAAALgADCgMJAwAAAA==.',
Cl='Claymordon:BAAALgADCgYJBgAAAA==.Clothpally:BAAALgAFFAEJAQAAAA==.',
Co='Codah:BAABLgAECn8WAAIOAAUJKwIRWgBAAAAOAAUJKwIRWgBAAAAAAA==.Contradict:BAAALgAECgYJBwABLgAECgkJMgAOAOwdAA==.Coomonka:BAAALgADCgcJCQAAAA==.Coraggioso:BAAALgADCgYJBgAAAA==.Corbenik:BAAALgAECgIJBgABLgAECgcJGAAGAPEHAA==.',
Cr='Creel:BAAALgADCgYJBgAAAA==.Crethasmus:BAAALgAECgYJCAAAAA==.Crettephal:BAEBLgAECn8bAAIVAAYJeRKdFgAUAQAVAAYJeRKdFgAUAQAAAA==.Crodo:BAAALgADCgYJBgAAAA==.Cruella:BAAALgAECgEJAQAAAA==.',
['Cä']='Cähira:BAAALgAECggJCgAAAA==.',
Da='Daellan:BAAALgAECgUJCQAAAA==.Dainaira:BAABLgAECn8XAAITAAkJywgnEADEAAATAAkJywgnEADEAAAAAA==.Daisia:BAABLgAECn8gAAIWAAkJyAa2JQBvAQAWAAkJyAa2JQBvAQAAAA==.Dalarrong:BAAALgAECgQJBAAAAA==.Dapanda:BAAALgAECgcJBgAAAA==.Dapandaz:BAAALgAECgkJBAAAAA==.Dasteaire:BAAALgAECgMJBgAAAA==.Daul:BAAALgAECgQJBAAAAA==.',
De='Deathdealler:BAABLgAECn8WAAMIAAgJvgL9+QC0AAAIAAgJiwL9+QC0AAACAAUJ+wGmUABSAAAAAA==.Deathstopper:BAAALgAECgYJBwABLgAECggJHAALANESAA==.Delti:BAAALgADCgEJAQABLgAECgkJHwAPAFcWAA==.Demonicadhd:BAAALgAECgYJEwAAAA==.Demonsmind:BAABLgAECn8ZAAMGAAgJphE8egBFAQAGAAcJwBA8egBFAQAHAAMJqhEuQQCwAAAAAA==.Derien:BAABLgAECn8vAAISAAkJqRf7AgDEAQASAAkJqRf7AgDEAQAAAA==.Derienfu:BAAALgAECgYJBgAAAA==.Devlyn:BAAALgAECgQJBwAAAA==.Devour:BAAALgAFFAEJAQABLgAFFAIJAgAQAAAAAA==.Dezin:BAAALgAECgYJCAAAAA==.',
Di='Dinkeldorf:BAAALgAECgMJBAABLgAFFAIJAgAQAAAAAA==.',
Dk='Dkerien:BAAALgAECggJCAAAAA==.',
Do='Donkeyteeth:BAABLgAECn8kAAIXAAkJag/CLgCGAQAXAAkJag/CLgCGAQAAAA==.Downtownbuu:BAAALgAECgQJBgAAAA==.',
Dr='Dracarian:BAAALgADCgMJAwAAAA==.Dracorz:BAAALgAECgYJCwAAAA==.Draqula:BAAALgAECgkJAgAAAA==.Dru:BAAALgADCgcJBwAAAA==.Drusila:BAAALgAECgEJAQAAAA==.Drywater:BAABLgAECn88AAIYAAkJNBGsFgAlAQAYAAkJNBGsFgAlAQAAAA==.',
Du='Duck:BAAALgAECgQJBAABLgAFFAIJAgAQAAAAAA==.Dura:BAABLgAECn83AAIEAAkJnBbzCQCcAQAEAAkJnBbzCQCcAQAAAA==.',
El='Eldermoon:BAAALgAFFAIJAgAAAA==.Eldunari:BAAALgAECgQJBAAAAA==.Elfblood:BAABLgAECn9HAAIHAAkJcQxtDwBJAQAHAAkJcQxtDwBJAQAAAA==.Elite:BAAALgAECgEJAQAAAA==.Elvion:BAAALgAECgMJBQAAAA==.',
Em='Emollama:BAABLgAECn9EAAMIAAkJyg0EVwDAAQAIAAkJyg0EVwDAAQACAAEJJwJpTQAcAAAAAA==.',
En='Engine:BAAALgADCgQJBAAAAA==.',
Ep='Ephimyra:BAAALgAECgQJCAAAAA==.',
Er='Eranae:BAAALgAECgIJAgAAAA==.Erazer:BAAALgADCgMJAwAAAA==.Erílana:BAAALgAECgYJCwAAAA==.',
Et='Etiimasi:BAAALgADCgYJBwAAAA==.Ettolrahc:BAAALgAECgUJBQAAAA==.',
Ev='Evanniá:BAABLgAECn81AAMZAAgJDA1rIADhAAAZAAgJDA1rIADhAAAWAAQJfALyVABaAAAAAA==.',
Ex='Expartaku:BAAALgADCgEJAQAAAA==.',
Ez='Ezanot:BAAALgADCgYJBgAAAA==.',
['Eï']='Eïr:BAAALgAECgQJCAABLgAFFAIJAgAQAAAAAA==.',
Fa='Fabulosa:BAABLgAECn8tAAQTAAgJtAxBMgBSAQATAAgJtAxBMgBSAQAaAAYJ2wnjLwAhAQAKAAUJYAqwVgCBAAAAAA==.Faith:BAABLgAECn8iAAIOAAkJwxq5dACEAQAOAAkJwxq5dACEAQAAAA==.',
Fe='Femidan:BAAALgAECgEJAQABLgAECgEJAgAQAAAAAA==.',
Fi='Finiquito:BAAALgADCgMJAwAAAA==.Finite:BAAALgAECgYJBwABLgAECgkJMgAOAOwdAA==.',
Fn='Fndruid:BAAALgAECgEJAgAAAA==.Fnmage:BAAALgAECgYJEwAAAA==.Fnshaman:BAAALgAECgYJEgAAAA==.',
Fo='Fourscore:BAAALgADCgMJAwAAAA==.',
Fr='Frieren:BAAALgAFFAIJAgABLgAFFAYJIgAbAEYjAA==.',
Fu='Furnok:BAABLgAECn9BAAMXAAkJ3xZ9FwApAgAXAAkJ3xZ9FwApAgAEAAcJMw0KZgApAQAAAA==.Fuzzyshukk:BAAALgAECgcJDgAAAA==.',
Ga='Galethia:BAAALgADCgkJMQAAAA==.Garli:BAAALgADCgMJAwAAAA==.Garmjackyl:BAAALgAECgEJAQAAAA==.',
Ge='Gerkin:BAAALgADCgcJDwAAAA==.',
Gg='Ggcthulhu:BAAALgAECgMJBQABLgAFFAQJBwAcAJ8IAA==.',
Gh='Ghutz:BAACLgAFFH8hAAMdAAQJIBThDAD0AAAdAAQJIBThDAD0AAASAAQJYAIfFACDAAAuAAQKfzwABB0ACQm6F+cNAAsCAB0ACQm6F+cNAAsCAB4ABwmICzZIAIMBABIAAgnHBzIPAGEAAAAA.',
Gl='Glitterhoof:BAABLgAECn8gAAIJAAkJjxkzGABGAgAJAAkJjxkzGABGAgAAAA==.Glorblariirn:BAAALgADCgYJBgAAAA==.Glumshanks:BAAALgAECgMJAwAAAA==.',
Go='Goliath:BAAALgAECgUJCwAAAA==.Gonja:BAAALgADCgcJFQAAAA==.Gonzaga:BAAALgADCgUJBQAAAA==.',
Gr='Grimbjorne:BAAALgADCgcJBwAAAA==.Grimmbeardd:BAAALgADCgYJCgAAAA==.',
Gu='Gumbercules:BAABLgAECn9HAAIcAAkJahOVDAAMAgAcAAkJahOVDAAMAgAAAA==.',
Ha='Hammie:BAAALgADCgkJCQAAAA==.',
He='Hearthglen:BAABLgAECn8hAAIOAAkJOxNpXAC5AQAOAAkJOxNpXAC5AQAAAA==.',
Ho='Hollet:BAABLgAECn82AAIZAAkJLRO2CgDMAQAZAAkJLRO2CgDMAQAAAA==.Holyblasto:BAAALgADCgEJAQAAAA==.Holyshukk:BAACLgAFFH8TAAIJAAYJVByuCgALAgAJAAYJVByuCgALAgAuAAQKfycAAwkACQmRIqEFABIDAAkACQmRIqEFABIDAA4AAQlCBwSzASgAAAEuAAQKBwkOABAAAAAA.',
Hu='Huckk:BAAALgAECgUJBQAAAA==.',
Hy='Hylen:BAACLgAFFH8FAAIVAAIJOBNjCACgAAAVAAIJOBNjCACgAAAuAAQKfxgAAhUACQnuFaQOAHEBABUACQnuFaQOAHEBAAAA.',
Ib='Ibrandul:BAABLgAECn89AAIOAAkJwRl+TADhAQAOAAkJwRl+TADhAQAAAA==.',
Ic='Icyveins:BAABLgAECn8UAAIYAAcJ8wEyDAGaAAAYAAcJ8wEyDAGaAAAAAA==.',
Ir='Iroha:BAAALgADCgQJBgAAAA==.Ironhuntress:BAABLgAECn8kAAIZAAkJThIcFABDAQAZAAkJThIcFABDAQAAAA==.',
It='Ithro:BAABLgAECn8pAAIfAAkJJxiGBQAeAgAfAAkJJxiGBQAeAgAAAA==.',
Iy='Iyachtu:BAAALgAECgkJEwAAAA==.',
Ja='Jaciel:BAAALgAECgcJBwAAAA==.Jarlo:BAABLgAECn9HAAIfAAkJ1xtfAwCAAgAfAAkJ1xtfAwCAAgAAAA==.',
Je='Jeffeory:BAAALgAECgIJAgABLgAECgkJFgAWAEEXAA==.Jefficiently:BAABLgAECn8WAAMWAAkJQRfjAgCkAQAWAAgJIBLjAgCkAQAZAAgJfBfmDQCSAQAAAA==.Jefriel:BAAALgAECgYJBgABLgAECgkJFgAWAEEXAA==.Jezzi:BAAALgAECgMJAwAAAA==.',
Jo='Jobu:BAAALgAECgEJAgAAAA==.Jormungandr:BAABLgAECn80AAMdAAkJFSJeBQC1AgAdAAkJ1CFeBQC1AgASAAcJDRuoEgDBAQAAAA==.',
Ju='Juandolf:BAAALgAECgUJBgAAAA==.Juanhunglow:BAAALgAECgMJBwAAAA==.Judgederien:BAAALgAECgIJAgAAAA==.Jularity:BAAALgADCgYJBgAAAA==.',
Ka='Kaeldric:BAABLgAECn81AAMIAAkJ5CI9BQA+AgAIAAkJ5CI9BQA+AgACAAEJ/w9VYQAnAAAAAA==.Kairilynn:BAAALgAECgMJAwAAAA==.Kaladïn:BAAALgAECgEJAQAAAA==.Kalemshai:BAAALgADCgcJCwAAAA==.Kalinea:BAABLgAECn9HAAIZAAgJWhdhCwC8AQAZAAgJWhdhCwC8AQAAAA==.Karyia:BAAALgAECgUJBQAAAA==.Kayvaan:BAAALgAECgYJCAAAAA==.Kazuha:BAAALgAECgYJDgAAAA==.',
Ke='Keegh:BAAALgAECgcJBwAAAA==.Kellerun:BAAALgAECgIJAgAAAA==.Keruptadin:BAAALgAECgUJBgAAAA==.Ketosis:BAAALgAECggJCQAAAA==.Keynnes:BAAALgAECgQJCAAAAA==.',
Kh='Khedriss:BAAALgAECgYJDgABLgAECgkJIwAIACARAA==.',
Ki='Kintha:BAAALgAECgYJBgAAAA==.',
Ko='Kope:BAABLgAECn80AAMcAAkJthtSAQAjAgAcAAkJthtSAQAjAgAbAAEJuhFKHAA0AAAAAA==.',
Kr='Kreltor:BAABLgAECn8vAAIEAAkJoSLjDQDnAgAEAAkJoSLjDQDnAgAAAA==.Kryptikz:BAABLgAECn8VAAMCAAkJXAsSJgAjAQACAAkJnQkSJgAjAQAIAAQJVhA05QC1AAAAAA==.Krystoferson:BAABLgAECn8oAAIgAAgJZgOADwB8AAAgAAgJZgOADwB8AAAAAA==.',
Ky='Kyrinea:BAAALgAECgMJAwAAAA==.',
La='Lalatína:BAAALgAECgMJAwAAAA==.Largar:BAAALgADCgUJCAAAAA==.Latem:BAAALgAECgEJAQAAAA==.',
Le='Leerroyy:BAAALgADCgIJAgAAAA==.Leesoftpaw:BAAALgADCgYJAgABLgAECgEJAgAQAAAAAA==.Leianii:BAABLgAECn8ZAAIWAAgJCwJTQgC6AAAWAAgJCwJTQgC6AAAAAA==.Lextali:BAAALgAECgQJBAAAAA==.',
Lh='Lhondar:BAAALgAECgYJDwAAAA==.',
Li='Liafail:BAABLgAECn8YAAIGAAcJ8QesgwBTAQAGAAcJ8QesgwBTAQAAAA==.Likkaru:BAAALgAECgIJAwAAAA==.Lillat:BAABLgAECn8XAAIKAAcJTg7PMgA+AQAKAAcJTg7PMgA+AQAAAA==.Lin:BAAALgAECgEJAQAAAA==.Liryv:BAAALgADCgYJFAAAAA==.Littlepop:BAAALgAECgUJBAAAAA==.',
Lo='Lollilock:BAAALgAECgcJBAAAAA==.',
Lu='Luena:BAAALgAECgYJEgAAAA==.Lugglugg:BAAALgAECgQJBAAAAA==.Lumbre:BAAALgADCgcJCQAAAA==.Luminara:BAAALgAECgcJDgAAAA==.Luuggork:BAAALgAECgMJCAAAAA==.',
Ly='Lyarith:BAAALgAECgMJAwAAAA==.Lyrà:BAAALgAECgQJAwAAAA==.',
['Lá']='Ládydèath:BAAALgAECgYJBwAAAA==.',
['Lä']='Lädygaga:BAAALgAECgMJBAAAAA==.',
['Lì']='Lìesson:BAABLgAECn85AAIOAAkJiCEQEQDeAgAOAAkJiCEQEQDeAgAAAA==.',
Ma='Mabo:BAAALgAECgEJAQAAAA==.Mackaroni:BAACLgAFFH8HAAIYAAQJWhBpaAATAQAYAAQJWhBpaAATAQAuAAQKfx4AAxgACQndFyljALgBABgACAlSFiljALgBACEAAwk+FqwHAJ0AAAEuAAUUAgkCABAAAAAA.Madolynne:BAAALgADCgIJAgAAAA==.Madrel:BAAALgADCgUJBQAAAA==.Magesca:BAABLgAECn9PAAIYAAkJkRs9KQB1AgAYAAkJkRs9KQB1AgAAAA==.Magimiester:BAAALgADCgEJAQABLgAECgcJIAAUAC8QAA==.Mahalath:BAAALgADCgMJAwAAAA==.Mahng:BAAALgADCgMJAwAAAA==.Makkagg:BAACLgAFFH8cAAMSAAUJrBtvEgAUAQASAAQJvRlvEgAUAQAeAAUJdQ8iHADHAAAuAAQKfzsAAxIACQkiIUQFAMYCABIACQkiIUQFAMYCAB4ACAlWDMc5AL8BAAAA.Malamur:BAAALgADCggJEgAAAA==.Malisea:BAABLgAECn8lAAIYAAkJswhjeQCGAQAYAAkJswhjeQCGAQAAAA==.Malistrace:BAAALgADCgEJAQAAAA==.',
Me='Melarndra:BAAALgADCgYJBgAAAA==.Melynea:BAAALgADCgEJAQAAAA==.Merillion:BAAALgAECgYJBgAAAA==.',
Mi='Milagrosa:BAABLgAECn8lAAIbAAkJ6w5rLwB7AQAbAAkJ6w5rLwB7AQAAAA==.Mirael:BAACLgAFFH8UAAIZAAYJqRg4HwCHAQAZAAYJqRg4HwCHAQAuAAQKfzkAAhkACQm7IcAIAAcDABkACQm7IcAIAAcDAAAA.Mishuntsalot:BAAALgAECgQJBQABLgAECggJCgAQAAAAAA==.Misstakes:BAAALgAECgMJAwAAAA==.',
Mo='Molocherx:BAAALgADCgMJAwAAAA==.Mommacoo:BAABLgAECn8iAAIOAAcJdQw22ADoAAAOAAcJdQw22ADoAAAAAA==.Mori:BAAALgAECgEJAQAAAA==.',
Mu='Mumbletung:BAAALgAECgkJAQAAAA==.',
My='Myrmia:BAABLgAECn8aAAIMAAcJvg1iWAAvAQAMAAcJvg1iWAAvAQAAAA==.Mystfang:BAABLgAECn8cAAIYAAkJihQoTwDuAQAYAAkJihQoTwDuAQAAAA==.',
['Mà']='Màck:BAAALgAFFAIJAgAAAA==.',
Na='Nade:BAAALgAECgcJBAAAAA==.Nargul:BAABLgAECn8vAAIGAAcJbRv4QADZAQAGAAcJbRv4QADZAQAAAA==.Naturboom:BAAALgAECgEJAQAAAA==.',
Ne='Nekossian:BAAALgAECgYJCwABLgAECgkJFgAWAEEXAA==.',
Ni='Nickorvis:BAAALgADCgUJBQABLgAECgcJGAAGAPEHAA==.Nirazen:BAAALgAECgIJBAAAAA==.',
No='Noburin:BAAALgADCgQJBAAAAA==.Nonae:BAEALgADCgYJBgAAAA==.Nota:BAABLgAECn8gAAIOAAkJswdrLAClAAAOAAkJswdrLAClAAAAAA==.',
Oa='Oathmere:BAAALgAECgQJBgAAAA==.',
Og='Ogrusao:BAABLgAECn8nAAIZAAkJtw1dGAAfAQAZAAkJtw1dGAAfAQAAAA==.Ogun:BAAALgADCgcJCgAAAA==.',
Or='Orukai:BAAALgAECgIJAgAAAA==.',
Pa='Panasaurus:BAABLgAECn9HAAIiAAkJ0RVeCADuAQAiAAkJ0RVeCADuAQAAAA==.',
Pe='Pechuuga:BAABLgAECn8WAAIjAAcJwBmCMgCHAQAjAAcJwBmCMgCHAQAAAA==.Pelli:BAABLgAECn81AAITAAkJkwnMCwABAQATAAkJkwnMCwABAQAAAA==.Pendraig:BAAALgAECgYJDAAAAA==.Pestilense:BAAALgADCgIJAgAAAA==.',
Pl='Plaza:BAABLgAFFH8JAAIIAAMJoBINQQDcAAAIAAMJoBINQQDcAAAAAA==.',
Qi='Qishawi:BAAALgAECgEJAQAAAA==.',
Qu='Quadrilio:BAAALgADCgUJBQAAAA==.Quamutei:BAAALgADCgUJBgAAAA==.',
Ra='Raylisarri:BAAALgAECgYJCQAAAA==.Rayst:BAABLgAECn9BAAIYAAgJ/wUVKQCyAAAYAAgJ/wUVKQCyAAAAAA==.Razìel:BAAALgADCgMJAgAAAA==.',
Rh='Rhalek:BAACLgAFFH8LAAIMAAUJOg9ZFgDEAAAMAAUJOg9ZFgDEAAAuAAQKfzEAAgwACQm3IMoBAL0CAAwACQm3IMoBAL0CAAAA.Rheunae:BAAALgAECgQJBAAAAA==.Rhykis:BAABLgAECn8lAAMeAAkJMCOHCQDKAgAeAAkJiiKHCQDKAgASAAMJcBq6BwDlAAAAAA==.',
Ri='Rilis:BAAALgADCgEJAQAAAA==.Rillyn:BAABLgAECn86AAMWAAkJKhdEDwA5AgAWAAkJxhZEDwA5AgAZAAEJ+hRPJAE7AAAAAA==.',
Ro='Rojei:BAAALgADCgYJBgAAAA==.Role:BAAALgADCgEJAQABLgAECggJLgAkAGUZAA==.',
Ru='Rubbin:BAAALgAECgEJAQAAAA==.',
['Rã']='Rãyné:BAAALgAECgkJAQAAAA==.',
Sa='Sabba:BAAALgADCgYJBgAAAA==.Sagearian:BAAALgAECggJEgAAAA==.Salindill:BAAALgADCgMJAwAAAA==.Samanda:BAABLgAECn8iAAIlAAcJ7RPUFQBrAQAlAAcJ7RPUFQBrAQAAAA==.Samshir:BAABLgAECn8jAAIIAAkJIBHGCQClAQAIAAkJIBHGCQClAQAAAA==.Sanzel:BAAALgAECgUJCQAAAA==.Sarinna:BAAALgAECgEJAQAAAA==.',
Sc='Scorned:BAABLgAECn8zAAIPAAgJBBMIUACVAQAPAAgJBBMIUACVAQAAAA==.Scratchddisc:BAAALgAECgEJAQABLgAECgEJAgAQAAAAAA==.',
Se='Sekrain:BAAALgAECgQJBAAAAA==.Seocharang:BAAALgAECgcJCwAAAA==.Seosinz:BAABLgAECn8cAAINAAYJUhSzPAAeAQANAAYJUhSzPAAeAQAAAA==.',
Sh='Shadowmane:BAAALgAECgEJAQAAAA==.Shamnasty:BAAALgAECgcJEwAAAA==.Shariaan:BAAALgAECgYJCQAAAA==.Shaylinn:BAABLgAECn8UAAIFAAUJWg/2BQC0AAAFAAUJWg/2BQC0AAAAAA==.Shenanigan:BAAALgADCgEJAQABLgAECgkJMgAOAOwdAA==.Shiviya:BAAALgADCgMJAwAAAA==.Shukkle:BAAALgAECgQJBAABLgAECgcJDgAQAAAAAA==.Shukkvoker:BAAALgADCgQJBQABLgAECgcJDgAQAAAAAA==.Shùkkle:BAABLgAECn8WAAINAAkJTx6VAQCtAgANAAkJTx6VAQCtAgAAAA==.',
Si='Siella:BAABLgAECn83AAIKAAkJoBJ9IAC+AQAKAAkJoBJ9IAC+AQAAAA==.Sileves:BAAALgAECgEJAgAAAA==.Sinyas:BAAALgADCgYJBgAAAA==.Sitrom:BAAALgAECgUJCwAAAA==.',
Sn='Snayd:BAABLgAECn8yAAMYAAkJKCHiHwCfAgAYAAgJfiHiHwCfAgAmAAcJBxgcAQBiAQAAAA==.Snowette:BAAALgADCgMJAwAAAA==.',
So='Solar:BAAALgAFFAIJAgABLgAFFAUJBgAPAMcBAA==.Somenai:BAAALgAECgQJBQAAAA==.Sonofmums:BAAALgAECgkJEAAAAA==.Sora:BAAALgAECgEJAQAAAA==.Soulbaine:BAABLgAECn8aAAMCAAcJuBbsGgCGAQACAAcJuBbsGgCGAQAIAAQJRhLk8QC+AAAAAA==.',
Sp='Spazeric:BAABLgAECn8oAAQLAAkJzxRlHwAfAgALAAkJzxRlHwAfAgAnAAcJKBawMwA1AQAjAAQJgQZ7CQCbAAAAAA==.Spheria:BAABLgAECn8/AAIGAAkJAAnFagBnAQAGAAkJAAnFagBnAQAAAA==.',
St='Stalon:BAAALgADCgYJDgAAAA==.Stevyn:BAAALgAECgEJAQAAAA==.Strangeluve:BAAALgAECgcJEQAAAA==.',
Su='Suerte:BAAALgADCggJDQAAAA==.Sunadora:BAAALgADCgUJBQAAAA==.Suzieq:BAAALgADCgMJBgAAAA==.',
Sy='Sysnootles:BAAALgADCgYJBwAAAA==.',
['Sà']='Sàyori:BAAALgAECgUJBwAAAA==.',
Ta='Tabrett:BAAALgAECgIJAgAAAA==.Talashara:BAAALgADCgEJAQAAAA==.Talashea:BAAALgAECgUJCAAAAA==.Tankdezoe:BAAALgAECgMJBAABLgAECggJEwAQAAAAAA==.Tarall:BAAALgAECgEJAQABLgAECgEJAQAQAAAAAA==.Taveres:BAAALgADCgEJAQAAAA==.Tax:BAABLgAECn89AAIVAAgJJQnwFQAbAQAVAAgJJQnwFQAbAQAAAA==.',
Te='Tenara:BAAALgADCgkJEgAAAA==.Tequ:BAABLgAECn8UAAMdAAUJJgpeDwB+AAAdAAUJQwleDwB+AAASAAMJygfUDgBkAAAAAA==.',
Ti='Tiche:BAABLgAECn8cAAILAAgJ0RJtBwC9AQALAAgJ0RJtBwC9AQAAAA==.Tim:BAABLgAFFH8GAAIEAAMJ0RbVSwDDAAAEAAMJ0RbVSwDDAAAAAA==.Timeshade:BAAALgAECgUJCgAAAA==.Timeshadow:BAABLgAECn8fAAMgAAYJoQO5QADCAAAgAAYJhwO5QADCAAAfAAEJxgMlCwAeAAAAAA==.Tinakoffee:BAAALgAECgIJAgAAAA==.Tine:BAABLgAECn8qAAIYAAkJ4xcsRQALAgAYAAkJ4xcsRQALAgAAAA==.',
To='Tope:BAAALgAECgYJCwAAAA==.Toray:BAABLgAECn8iAAIOAAgJbBNnagCaAQAOAAgJbBNnagCaAQAAAA==.',
Tr='Triplesix:BAABLgAECn8ZAAMoAAkJLBKrKAA3AQAoAAkJLBKrKAA3AQAPAAcJ8AS+sgDDAAAAAA==.Trittia:BAABLgAECn9MAAMeAAkJBhcFAwAkAgAeAAkJtxYFAwAkAgASAAUJfA6iCADJAAAAAA==.',
Tu='Tukk:BAABLgAECn8VAAMSAAcJGxI3HwA5AQASAAcJ4hE3HwA5AQAdAAEJwArdgQAoAAAAAA==.Turtle:BAAALgAECgEJBQAAAA==.',
Tw='Twigatron:BAABLgAECn8VAAIMAAgJCBUYLwDoAQAMAAgJCBUYLwDoAQABLgAECgcJEQAQAAAAAA==.Twigdin:BAAALgADCgMJAwAAAA==.Twigdun:BAAALgAECgMJBgAAAA==.',
Ty='Tynk:BAAALgAECgkJEwAAAA==.Tythus:BAAALgADCgIJAgAAAA==.',
Ur='Urza:BAAALgAECgYJCgAAAA==.',
Va='Vaewind:BAAALgADCgMJAwAAAA==.Valethus:BAABLgAECn8+AAMZAAkJZSBKAwDCAgAZAAkJZSBKAwDCAgAFAAIJVAgefgBNAAAAAA==.Valmaru:BAAALgADCgkJCQAAAA==.',
Ve='Velleria:BAAALgAECgEJAQAAAA==.Verlis:BAAALgAECgIJAgAAAA==.Vesp:BAAALgAECgQJBQAAAA==.Vexxa:BAABLgAECn8YAAIPAAkJPBgASwClAQAPAAkJPBgASwClAQAAAA==.Veylla:BAAALgAECgEJAQABLgAECgcJGQAoAHwKAA==.',
Vi='Viridania:BAAALgAECgUJEAAAAA==.',
Vy='Vynd:BAAALgAECgMJBQABLgAECgkJDwAQAAAAAA==.',
Wa='Walkz:BAABLgAECn8VAAISAAYJ/B0EBQBJAQASAAYJ/B0EBQBJAQABLgAECgkJFQACAFwLAA==.Warrockhealz:BAAALgADCgYJBgAAAA==.',
Wi='Wickedlight:BAABLgAECn9BAAITAAkJhCAJBgDyAgATAAkJhCAJBgDyAgAAAA==.Wickedlock:BAAALgAECgQJCQAAAA==.Wiggleston:BAACLgAFFH8IAAIJAAMJKw7BGwB6AAAJAAMJKw7BGwB6AAAuAAQKfywABAkACQluEmkgAAACAAkACQluEmkgAAACAA4AAwljA4tKAWMAABQAAQlkADwfAA4AAAEuAAQKCAkcAAsA0RIA.Willscarlet:BAABLgAECn8WAAIZAAcJFAVzpQD3AAAZAAcJFAVzpQD3AAAAAA==.',
Wo='Wollybully:BAAALgADCgQJCQABLgAECgcJIAAUAC8QAA==.',
Wy='Wylder:BAABLgAECn8aAAISAAcJDgeOLQDPAAASAAcJDgeOLQDPAAAAAA==.Wylethia:BAAALgAECgQJBAAAAA==.',
Xa='Xandris:BAAALgAECgEJAgABLgAECgkJIwAIACARAA==.',
Yf='Yffre:BAAALgAECgYJBgAAAA==.',
Yh='Yhana:BAAALgADCggJEwAAAA==.',
Yo='Yolifeismine:BAAALgAECgUJBQAAAA==.Yozsh:BAAALgAECgYJBgAAAA==.',
Za='Zamual:BAAALgAECgMJBAAAAA==.Zanthiava:BAAALgAECgYJBwAAAA==.Zarathia:BAABLgAECn8ZAAIoAAcJfAqjMgD4AAAoAAcJfAqjMgD4AAAAAA==.Zargar:BAAALgAECgEJAQAAAA==.Zaritym:BAABLgAECn8jAAMLAAkJJho2HQAuAgALAAkJJho2HQAuAgAnAAQJbw+7aACDAAAAAA==.Zarrilin:BAABLgAECn8oAAIYAAkJlBcpRQAMAgAYAAkJlBcpRQAMAgAAAA==.',
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
