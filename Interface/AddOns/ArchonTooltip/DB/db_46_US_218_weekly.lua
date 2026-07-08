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

local lookup = {'DeathKnight-Frost','DeathKnight-Blood','Shaman-Enhancement','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Paladin-Holy','Priest-Holy','Monk-Mistweaver','Druid-Restoration','Druid-Balance','DemonHunter-Devourer','Unknown-Unknown','Warrior-Protection','Paladin-Retribution','Priest-Shadow','Paladin-Protection','Warlock-Affliction','Hunter-Survival','Shaman-Elemental','Mage-Frost','Shaman-Restoration','Priest-Discipline','Evoker-Augmentation','Evoker-Preservation','Warrior-Arms','Warrior-Fury','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','Mage-Arcane','DemonHunter-Vengeance','Monk-Brewmaster','Rogue-Outlaw','Druid-Feral','Mage-Fire','Monk-Windwalker','DemonHunter-Havoc',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Absolver:BAAALgADCgYJCwAAAA==.',
Ad='Adabisi:BAAALgADCgQJCQAAAA==.Addu:BAAALgAECgUJBgAAAA==.Adiforis:BAABLgAECn8hAAMBAAkJlhAYDAC2AQABAAkJEhAYDAC2AQACAAUJawriPACdAAAAAA==.Adobo:BAACLgAFFH8MAAIDAAQJngfuBADlAAADAAQJngfuBADlAAAuAAQKfxUAAgMACQk+Ea4LAPkBAAMACQk+Ea4LAPkBAAAA.Adventures:BAAALgADCgIJAgAAAA==.',
Ae='Aeralina:BAABLgAECn8XAAIEAAgJpQmqFAAYAQAEAAgJpQmqFAAYAQAAAA==.Aerandir:BAABLgAECn8bAAMFAAYJewviDwClAAAFAAYJewviDwClAAAGAAEJAAAXeQAqAAABLgAECgkJHQAHAMIOAA==.Aerwyn:BAAALgAECgYJBgAAAA==.',
Ah='Ahmyra:BAAALgAECgcJEwAAAA==.',
Al='Alessar:BAAALgAECgYJDAAAAA==.Allysson:BAABLgAECn84AAIBAAkJMRTLCQDmAQABAAkJMRTLCQDmAQAAAA==.Alrekur:BAAALgAECgIJAgAAAA==.Alyestra:BAABLgAECn8ZAAIIAAgJzBEaLgClAQAIAAgJzBEaLgClAQAAAA==.',
Am='Ambien:BAAALgAECgYJCwAAAA==.',
An='Anibundance:BAAALgAECgcJDAABLgAECgkJLQAJAJ0iAA==.Animyst:BAACLgAFFH8JAAIKAAQJ8hx6JgA6AQAKAAQJ8hx6JgA6AQAuAAQKf0cAAgoACQlMJJwAAEIDAAoACQlMJJwAAEIDAAEuAAQKCQktAAkAnSIA.Anipaltu:BAACLgAFFH8IAAIIAAQJsAw0KQDcAAAIAAQJsAw0KQDcAAAuAAQKfx4AAggACQm2HQcJAPoCAAgACQm2HQcJAPoCAAEuAAQKCQktAAkAnSIA.Aniron:BAABLgAECn8UAAIFAAYJchEjjQAgAQAFAAYJchEjjQAgAQABLgAECgkJLQAJAJ0iAA==.Anirot:BAABLgAECn8tAAIJAAkJnSKSBAA3AwAJAAkJnSKSBAA3AwAAAA==.Anithwip:BAAALgAECgYJBgABLgAECgkJLQAJAJ0iAA==.Antoni:BAAALgAECgEJAQAAAA==.',
Ap='Aphirym:BAAALgAECgIJAgAAAA==.',
Ar='Aranta:BAABLgAECn8aAAMLAAYJmQ4yYQASAQALAAYJmQ4yYQASAQAMAAYJ9AlKUQDJAAAAAA==.Arcanium:BAAALgAECgEJAgAAAA==.',
As='Astren:BAAALgAECgcJEAAAAA==.Asynsia:BAABLgAECn8oAAINAAkJZiG1EAC8AgANAAkJZiG1EAC8AgAAAA==.',
Av='Avamani:BAAALgADCgkJCQAAAA==.',
Az='Azulmoon:BAAALgAECgYJCwAAAA==.',
Ba='Balrogg:BAAALgADCgcJBwAAAA==.Bartholomew:BAACLgAFFH8GAAIKAAQJVRBjMwDgAAAKAAQJVRBjMwDgAAAuAAQKfzMAAgoACQl+HtoLANsCAAoACQl+HtoLANsCAAAA.Bartno:BAAALgAECgIJAQAAAA==.',
Be='Beefed:BAAALgADCgIJAgAAAA==.Beertje:BAAALgAFFAMJBAABLgAFFAIJAgAOAAAAAA==.Bellathrix:BAAALgAECgMJAwAAAA==.Bessie:BAAALgADCgIJAgAAAA==.',
Bi='Bienfaiseur:BAABLgAECn9BAAIJAAkJjCU1AQC2AwAJAAkJjCU1AQC2AwAAAA==.Bigdamhero:BAAALgAECgIJAgAAAA==.Bigtonka:BAAALgADCgYJBgAAAA==.',
Bl='Bladez:BAAALgAECgYJBwAAAA==.',
Bo='Boffadeez:BAAALgAECgcJDAAAAA==.Boombawks:BAAALgADCgUJBQABLgAECgEJAgAOAAAAAA==.Boryndin:BAABLgAECn8iAAIPAAkJohkuDgAJAgAPAAkJohkuDgAJAgAAAA==.',
Br='Brad:BAAALgADCgIJAgAAAA==.Breadbringer:BAAALgADCgIJAgAAAA==.Breadburn:BAAALgADCggJCAAAAA==.Breezybb:BAACLgAFFH8NAAIQAAUJaREeSAAcAQAQAAUJaREeSAAcAQAuAAQKfzsAAhAACQlhHCw6ADoCABAACQlhHCw6ADoCAAAA.Brewfist:BAAALgADCgUJCAAAAA==.Brutonmage:BAAALgAECgcJBwAAAA==.',
Bu='Bulgrim:BAAALgADCggJEQAAAA==.',
Ca='Camhawk:BAAALgADCgkJCQAAAA==.Catastrophe:BAAALgAECgcJBwABLgAFFAIJAwAOAAAAAA==.',
Ce='Cearylin:BAAALgAECggJCAAAAA==.Cering:BAAALgAECgYJBgAAAA==.',
Ch='Changsauce:BAAALgAECgYJDAAAAA==.Cherypoptart:BAABLgAECn8kAAIRAAgJnSNVCQC5AgARAAgJnSNVCQC5AgAAAA==.Chrismeister:BAABLgAECn8ZAAQSAAYJAwxaMgCbAAASAAUJLQtaMgCbAAAIAAEJygtHlAArAAAQAAEJAABv2gEAAAAAAA==.',
Ci='Cing:BAAALgAECgEJAQAAAA==.',
Cl='Claymordon:BAAALgADCgYJBgAAAA==.Clothpally:BAAALgAFFAEJAQAAAA==.',
Co='Codah:BAABLgAECn8WAAIQAAUJKwLZMwBHAAAQAAUJKwLZMwBHAAAAAA==.Contradict:BAAALgAECgEJAQABLgAECgkJLgAQAKYdAA==.Coomonka:BAAALgADCgcJCQAAAA==.Coraggioso:BAAALgADCgYJBgAAAA==.Corbenik:BAAALgAECgIJBgABLgAECgcJGAAFAPEHAA==.',
Cr='Creel:BAAALgADCgYJBgAAAA==.Crethasmus:BAAALgAECgYJCAAAAA==.Crettephal:BAEBLgAECn8aAAITAAUJYxSdFgAUAQATAAUJYxSdFgAUAQAAAA==.Crodo:BAAALgADCgYJBgAAAA==.Cruella:BAAALgAECgEJAQAAAA==.',
['Cä']='Cähira:BAAALgAECgYJCAAAAA==.',
Da='Daellan:BAAALgAECgUJCQAAAA==.Dainaira:BAABLgAECn8XAAIRAAkJywgfBwDmAAARAAkJywgfBwDmAAAAAA==.Daisia:BAABLgAECn8gAAIUAAkJyAa2JQBvAQAUAAkJyAa2JQBvAQAAAA==.Dalarrong:BAAALgAECgQJBAAAAA==.Dapanda:BAAALgAECgcJBQAAAA==.Dasteaire:BAAALgAECgMJBgAAAA==.Daul:BAAALgADCgQJAQAAAA==.',
De='Deathdealler:BAABLgAECn8VAAMHAAgJvgL9+QC0AAAHAAgJewL9+QC0AAACAAUJ+wGmUABSAAAAAA==.Deathstopper:BAAALgAECgYJBwABLgAFFAIJBQAIAD8UAA==.Delti:BAAALgADCgEJAQABLgAECgkJHwANAFcWAA==.Demonicadhd:BAAALgAECgYJEwAAAA==.Demonsmind:BAABLgAECn8ZAAMFAAgJphE8egBFAQAFAAcJwBA8egBFAQAGAAMJqhEuQQCwAAAAAA==.Derien:BAABLgAECn8mAAIPAAgJQRglEgDIAQAPAAgJQRglEgDIAQAAAA==.Derienfu:BAAALgAECgYJBgAAAA==.Devour:BAAALgAFFAEJAQABLgAFFAIJAgAOAAAAAA==.Dezin:BAAALgAECgYJCAAAAA==.',
Di='Dinkeldorf:BAAALgAECgMJBAABLgAFFAIJAgAOAAAAAA==.',
Dk='Dkerien:BAAALgAECggJCAAAAA==.',
Do='Donkeyteeth:BAABLgAECn8kAAIVAAkJag/CLgCGAQAVAAkJag/CLgCGAQAAAA==.Downtownbuu:BAAALgADCgcJDAAAAA==.',
Dr='Dracarian:BAAALgADCgMJAwAAAA==.Dracorz:BAAALgAECgYJCwAAAA==.Dru:BAAALgADCgcJBwAAAA==.Drywater:BAABLgAECn88AAIWAAkJNBEnCwA7AQAWAAkJNBEnCwA7AQAAAA==.',
Du='Duck:BAAALgAECgQJBAABLgAFFAIJAgAOAAAAAA==.Dura:BAABLgAECn83AAIXAAkJnBapBACmAQAXAAkJnBapBACmAQAAAA==.',
El='Eldermoon:BAAALgAFFAIJAgAAAA==.Eldunari:BAAALgAECgQJBAAAAA==.Elfblood:BAABLgAECn9HAAIGAAkJcQxtDwBJAQAGAAkJcQxtDwBJAQAAAA==.Elite:BAAALgAECgEJAQAAAA==.Elvion:BAAALgAECgMJBQAAAA==.',
Em='Emollama:BAABLgAECn9EAAMHAAkJyg0EVwDAAQAHAAkJyg0EVwDAAQACAAEJJwJpTQAcAAAAAA==.',
En='Engine:BAAALgADCgQJBAAAAA==.',
Ep='Ephimyra:BAAALgAECgQJCAAAAA==.',
Er='Erazer:BAAALgADCgMJAwAAAA==.Erilana:BAAALgAECgYJCwAAAA==.',
Et='Etiimasi:BAAALgADCgYJBwAAAA==.',
Ex='Expartaku:BAAALgADCgEJAQAAAA==.',
Ez='Ezanot:BAAALgADCgYJBgAAAA==.',
['Eï']='Eïr:BAAALgAECgQJCAABLgAFFAIJAgAOAAAAAA==.',
Fa='Fabulosa:BAABLgAECn8tAAQRAAgJtAxBMgBSAQARAAgJtAxBMgBSAQAYAAYJ2wnjLwAhAQAJAAUJYAqwVgCBAAAAAA==.Faith:BAABLgAECn8hAAIQAAgJTxu5dACEAQAQAAgJTxu5dACEAQAAAA==.',
Fe='Femidan:BAAALgAECgEJAQABLgAECgEJAgAOAAAAAA==.',
Fi='Finiquito:BAAALgADCgMJAwAAAA==.Finite:BAAALgAECgYJBwABLgAECgkJLgAQAKYdAA==.Firebug:BAABLgAECn8aAAIPAAcJDgeOLQDPAAAPAAcJDgeOLQDPAAAAAA==.',
Fn='Fndruid:BAAALgADCgEJAQAAAA==.Fnmage:BAAALgAECgQJCwAAAA==.Fnshaman:BAAALgAECgYJCwAAAA==.',
Fo='Fourscore:BAAALgADCgMJAwAAAA==.',
Fr='Frieren:BAAALgAECgMJAwABLgAFFAYJIgAZAEYjAA==.',
Fu='Furnok:BAABLgAECn9BAAMVAAkJ3xZ9FwApAgAVAAkJ3xZ9FwApAgAXAAcJMw0KZgApAQAAAA==.Fuzzyshukk:BAAALgAECgcJDgAAAA==.',
Ga='Galethia:BAAALgADCgkJLQAAAA==.Garli:BAAALgADCgMJAwAAAA==.',
Ge='Gerkin:BAAALgADCgcJDwAAAA==.',
Gg='Ggcthulhu:BAAALgAECgMJBQABLgAFFAQJBwAaAJ8IAA==.',
Gh='Ghutz:BAACLgAFFH8XAAMbAAQJxwzRHgD8AAAbAAQJxwzRHgD8AAAPAAIJUAIqFABJAAAuAAQKfzoAAxsACQm6F+cNAAsCABsACQm6F+cNAAsCABwABwmICzZIAIMBAAAA.',
Gl='Glitterhoof:BAABLgAECn8gAAIIAAkJjxkzGABGAgAIAAkJjxkzGABGAgAAAA==.Glorblariirn:BAAALgADCgYJBgAAAA==.',
Go='Goliath:BAAALgAECgUJCwAAAA==.Gonja:BAAALgADCgcJFQAAAA==.',
Gr='Grimbjorne:BAAALgADCgcJBwAAAA==.Grimmbeardd:BAAALgADCgYJCgAAAA==.',
Gu='Gumbercules:BAABLgAECn9HAAIaAAkJahOVDAAMAgAaAAkJahOVDAAMAgAAAA==.',
Ha='Hammie:BAAALgADCgkJCQAAAA==.',
He='Hearthglen:BAABLgAECn8hAAIQAAkJOxNpXAC5AQAQAAkJOxNpXAC5AQAAAA==.',
Ho='Hollet:BAABLgAECn8xAAIdAAgJrhEpBwCVAQAdAAgJrhEpBwCVAQAAAA==.Holyblasto:BAAALgADCgEJAQAAAA==.Holyshukk:BAACLgAFFH8TAAIIAAYJVByuCgALAgAIAAYJVByuCgALAgAuAAQKfycAAwgACQmRIqEFABIDAAgACQmRIqEFABIDABAAAQlCBwSzASgAAAEuAAQKBwkOAA4AAAAA.',
Hu='Huckk:BAAALgAECgUJBQAAAA==.',
Hy='Hylen:BAABLgAECn8YAAITAAkJ7hWkDgBxAQATAAkJ7hWkDgBxAQAAAA==.',
Ib='Ibrandul:BAABLgAECn87AAIQAAgJ7xd+TADhAQAQAAgJ7xd+TADhAQAAAA==.',
Ic='Icyveins:BAABLgAECn8UAAIWAAcJ8wEyDAGaAAAWAAcJ8wEyDAGaAAAAAA==.',
Ir='Iroha:BAAALgADCgQJBgAAAA==.Ironhuntress:BAABLgAECn8kAAIdAAkJThJFCQBlAQAdAAkJThJFCQBlAQAAAA==.',
It='Ithro:BAABLgAECn8oAAIeAAkJJxiGBQAeAgAeAAkJJxiGBQAeAgAAAA==.',
Iy='Iyachtu:BAAALgAECgkJEwAAAA==.',
Ja='Jaciel:BAAALgAECgcJBwAAAA==.Jarlo:BAABLgAECn9HAAIeAAkJ1xtfAwCAAgAeAAkJ1xtfAwCAAgAAAA==.',
Je='Jeffeory:BAAALgAECgIJAgABLgAECgkJLQAQAMUaAA==.Jefficiently:BAAALgAECgcJDQABLgAECgkJLQAQAMUaAA==.Jefriel:BAAALgAECgYJBgABLgAECgkJLQAQAMUaAA==.Jezzi:BAAALgAECgMJAwAAAA==.',
Jo='Jobu:BAAALgAECgEJAgAAAA==.Jormungandr:BAABLgAECn80AAMbAAkJFSJeBQC1AgAbAAkJ1CFeBQC1AgAPAAcJDRuoEgDBAQAAAA==.',
Ju='Juanhunglow:BAAALgAECgMJBwAAAA==.Judgederien:BAAALgAECgIJAgAAAA==.Jularity:BAAALgADCgYJBgAAAA==.',
Ka='Kaeldric:BAABLgAECn81AAMHAAkJ5CKpAgBXAgAHAAkJ5CKpAgBXAgACAAEJ/w9VYQAnAAAAAA==.Kairilynn:BAAALgAECgEJAQAAAA==.Kaladïn:BAAALgAECgEJAQAAAA==.Kalemshai:BAAALgADCgcJCwAAAA==.Kalinea:BAABLgAECn85AAIdAAgJgxOjdABWAQAdAAgJgxOjdABWAQAAAA==.Karyia:BAAALgAECgUJBQAAAA==.Kazuha:BAAALgAECgYJDgAAAA==.',
Ke='Kellerun:BAAALgADCgIJAgAAAA==.Keruptadin:BAAALgAECgUJBgAAAA==.Ketosis:BAAALgADCggJCgAAAA==.',
Ki='Kintha:BAAALgAECgYJBgAAAA==.',
Ko='Kope:BAABLgAECn8rAAIaAAkJ/BoSBgCpAgAaAAkJ/BoSBgCpAgAAAA==.',
Kr='Kreltor:BAABLgAECn8vAAIXAAkJoSL+AQBbAgAXAAkJoSL+AQBbAgAAAA==.Kryptikz:BAABLgAECn8VAAMCAAkJXAsSJgAjAQACAAkJnQkSJgAjAQAHAAQJVhA05QC1AAAAAA==.Krystoferson:BAABLgAECn8hAAIfAAgJUwK2OADuAAAfAAgJUwK2OADuAAAAAA==.',
Ky='Kyrinea:BAAALgAECgMJAwAAAA==.',
La='Lalatína:BAAALgAECgEJAQAAAA==.Largar:BAAALgADCgUJCAAAAA==.',
Le='Leerroyy:BAAALgADCgIJAgAAAA==.Leesoftpaw:BAAALgADCgYJAgABLgAECgEJAgAOAAAAAA==.Leianii:BAABLgAECn8YAAIUAAgJCwJTQgC6AAAUAAgJCwJTQgC6AAAAAA==.Lextali:BAAALgAECgQJBAAAAA==.',
Lh='Lhondar:BAAALgAECgYJCQAAAA==.',
Li='Liafail:BAABLgAECn8YAAIFAAcJ8QesgwBTAQAFAAcJ8QesgwBTAQAAAA==.Likkaru:BAAALgAECgEJAQAAAA==.Lillat:BAABLgAECn8XAAIJAAcJTg7PMgA+AQAJAAcJTg7PMgA+AQAAAA==.Lin:BAAALgAECgEJAQAAAA==.Liryv:BAAALgADCgYJFAAAAA==.Littlepop:BAAALgAECgEJAQAAAA==.',
Lo='Lollilock:BAAALgAECgcJBAAAAA==.',
Lu='Luena:BAAALgAECgYJEgAAAA==.Lugglugg:BAAALgAECgQJBAAAAA==.Lumbre:BAAALgADCgcJCQAAAA==.Luminara:BAAALgAECgcJDgAAAA==.Luuggork:BAAALgAECgMJBgAAAA==.',
Ly='Lyarith:BAAALgAECgMJAwAAAA==.Lyrà:BAAALgAECgQJAwAAAA==.',
['Lá']='Ládydèath:BAAALgAECgYJBwAAAA==.',
['Lì']='Lìesson:BAABLgAECn85AAIQAAkJiCEQEQDeAgAQAAkJiCEQEQDeAgAAAA==.',
Ma='Mabo:BAAALgAECgEJAQAAAA==.Mackaroni:BAACLgAFFH8HAAIWAAQJWhBpaAATAQAWAAQJWhBpaAATAQAuAAQKfx4AAxYACQndFyljALgBABYACAlSFiljALgBACAAAwk+FoICAI4AAAEuAAUUAgkCAA4AAAAA.Madolynne:BAAALgADCgIJAgAAAA==.Madrel:BAAALgADCgUJBQAAAA==.Magesca:BAABLgAECn9OAAIWAAkJkRs7BgClAQAWAAkJkRs7BgClAQAAAA==.Magimiester:BAAALgADCgEJAQABLgAECgYJGQASAAMMAA==.Mahalath:BAAALgADCgMJAwAAAA==.Makkagg:BAACLgAFFH8cAAMPAAUJrBtvEgAUAQAPAAQJvRlvEgAUAQAcAAUJdQ9uEQDXAAAuAAQKfzUAAw8ACQkiIUQFAMYCAA8ACQkiIUQFAMYCABwACAlWDMc5AL8BAAAA.Malamur:BAAALgADCggJEgAAAA==.Malisea:BAABLgAECn8lAAIWAAkJswhjeQCGAQAWAAkJswhjeQCGAQAAAA==.',
Me='Melarndra:BAAALgADCgYJBgAAAA==.Melynea:BAAALgADCgEJAQAAAA==.Merillion:BAAALgAECgYJBgAAAA==.',
Mi='Milagrosa:BAABLgAECn8lAAIZAAkJ6w5rLwB7AQAZAAkJ6w5rLwB7AQAAAA==.Mirael:BAACLgAFFH8TAAIdAAYJqRg4HwCHAQAdAAYJqRg4HwCHAQAuAAQKfzkAAh0ACQm7IcAIAAcDAB0ACQm7IcAIAAcDAAAA.Mishuntsalot:BAAALgAECgQJBQABLgAECgYJCAAOAAAAAA==.',
Mo='Molocherx:BAAALgADCgMJAwAAAA==.Mommacoo:BAABLgAECn8hAAIQAAYJaAo22ADoAAAQAAYJaAo22ADoAAAAAA==.Mori:BAAALgAECgEJAQAAAA==.',
Mu='Mumbletung:BAAALgAECgkJAQAAAA==.Mumsms:BAAALgAECgkJBgAAAA==.Mumsurprise:BAAALgAECgkJAgAAAA==.',
My='Myrmia:BAABLgAECn8aAAILAAcJvg1iWAAvAQALAAcJvg1iWAAvAQAAAA==.Mystfang:BAABLgAECn8cAAIWAAkJihQoTwDuAQAWAAkJihQoTwDuAQAAAA==.',
['Mà']='Màck:BAAALgAFFAIJAgAAAA==.',
Na='Nade:BAAALgAECgcJBAAAAA==.Nargul:BAABLgAECn8vAAIFAAcJbRv4QADZAQAFAAcJbRv4QADZAQAAAA==.Naturboom:BAAALgAECgEJAQAAAA==.',
Ne='Nekossian:BAAALgAECgYJCwABLgAECgkJLQAQAMUaAA==.',
Ni='Nickorvis:BAAALgADCgUJBQABLgAECgcJGAAFAPEHAA==.Nirazen:BAAALgAECgIJAgAAAA==.',
No='Nonae:BAEALgADCgYJBgAAAA==.Nota:BAABLgAECn8gAAIQAAkJswc9FgC+AAAQAAkJswc9FgC+AAAAAA==.',
Oa='Oathmere:BAAALgAECgQJBQAAAA==.',
Og='Ogrusao:BAABLgAECn8nAAIdAAkJtw2PCwA9AQAdAAkJtw2PCwA9AQAAAA==.Ogun:BAAALgADCgcJCgAAAA==.',
Or='Orukai:BAAALgAECgIJAgAAAA==.',
Pa='Panasaurus:BAABLgAECn9HAAIhAAkJ0RVeCADuAQAhAAkJ0RVeCADuAQAAAA==.',
Pe='Pechuuga:BAABLgAECn8WAAIiAAcJwBmCMgCHAQAiAAcJwBmCMgCHAQAAAA==.Pelli:BAABLgAECn81AAIRAAkJkwkhBQAkAQARAAkJkwkhBQAkAQAAAA==.Pendraig:BAAALgAECgYJDAAAAA==.Pestilense:BAAALgADCgIJAgAAAA==.',
Pl='Plaza:BAAALgAECgkJEwAAAA==.',
Qu='Quadrilio:BAAALgADCgUJBQAAAA==.Quamutei:BAAALgADCgUJBgAAAA==.',
Ra='Raylisarri:BAAALgAECgEJAgABLgAECgUJIAAGAE0NAA==.Rayst:BAABLgAECn89AAIWAAgJIQW3GgCfAAAWAAgJIQW3GgCfAAAAAA==.Razìel:BAAALgADCgMJAgAAAA==.',
Rh='Rhalek:BAACLgAFFH8GAAILAAMJhxL0QQCqAAALAAMJhxL0QQCqAAAuAAQKfyUAAgsACAmuIesMAPYCAAsACAmuIesMAPYCAAEuAAUUBAkSAAsAxxQA.Rheunae:BAAALgAECgQJBAAAAA==.Rhykis:BAABLgAECn8lAAMcAAkJMCOHCQDKAgAcAAkJiiKHCQDKAgAPAAMJcBrxAwDvAAAAAA==.',
Ri='Rilis:BAAALgADCgEJAQAAAA==.Rillyn:BAABLgAECn86AAMUAAkJKhdEDwA5AgAUAAkJxhZEDwA5AgAdAAEJ+hRPJAE7AAAAAA==.',
Ro='Rojei:BAAALgADCgYJBgAAAA==.Role:BAAALgADCgEJAQABLgAECggJLgAjAGUZAA==.',
Ru='Rubbin:BAAALgAECgEJAQAAAA==.',
Sa='Sabba:BAAALgADCgYJBgAAAA==.Sagearian:BAAALgAECggJEgAAAA==.Salindill:BAAALgADCgMJAwAAAA==.Salline:BAABLgAECn81AAMdAAgJDA31EQDsAAAdAAgJDA31EQDsAAAUAAQJfALyVABaAAAAAA==.Samanda:BAABLgAECn8iAAIkAAcJ7RPUFQBrAQAkAAcJ7RPUFQBrAQAAAA==.Samshir:BAABLgAECn8dAAIHAAkJwg5mEQDQAAAHAAkJwg5mEQDQAAAAAA==.Sanzel:BAAALgAECgQJCAAAAA==.',
Sc='Scorned:BAABLgAECn8zAAINAAgJBBMIUACVAQANAAgJBBMIUACVAQAAAA==.Scratchddisc:BAAALgAECgEJAQABLgAECgEJAgAOAAAAAA==.',
Se='Sekrain:BAAALgAECgQJBAAAAA==.Seocharang:BAAALgAECgQJBAAAAA==.Seosinz:BAABLgAECn8bAAIMAAYJ5BKzPAAeAQAMAAYJ5BKzPAAeAQAAAA==.',
Sh='Shadowmane:BAAALgAECgEJAQAAAA==.Shamnasty:BAAALgAECgcJEwAAAA==.Shariaan:BAAALgAECgYJCQAAAA==.Shaylinn:BAAALgAECgMJCQAAAA==.Shenanigan:BAAALgADCgEJAQABLgAECgkJLgAQAKYdAA==.Shukkvoker:BAAALgADCgQJBQABLgAECgcJDgAOAAAAAA==.Shùkkle:BAAALgAFFAEJAgAAAA==.',
Si='Siella:BAABLgAECn83AAIJAAkJoBJDBQAcAQAJAAkJoBJDBQAcAQAAAA==.Sileves:BAAALgAECgEJAgABLgAECgYJCwAOAAAAAA==.Sinyas:BAAALgADCgYJBgAAAA==.Sitrom:BAAALgAECgUJCwAAAA==.',
Sn='Snayd:BAABLgAECn8yAAMWAAkJKCHiHwCfAgAWAAgJfiHiHwCfAgAlAAcJBxiRAABnAQAAAA==.Snowette:BAAALgADCgIJAgAAAA==.',
So='Solar:BAAALgAFFAIJAgAAAA==.Somenai:BAAALgAECgQJBQAAAA==.Sonofmums:BAAALgAECgkJBgAAAA==.Sora:BAAALgAECgEJAQAAAA==.Soulbaine:BAABLgAECn8aAAMCAAcJuBbsGgCGAQACAAcJuBbsGgCGAQAHAAQJRhLk8QC+AAAAAA==.',
Sp='Spazeric:BAABLgAECn8oAAQKAAkJzxRlHwAfAgAKAAkJzxRlHwAfAgAmAAcJKBawMwA1AQAiAAQJgQa3BQCkAAAAAA==.Spheria:BAABLgAECn8/AAIFAAkJAAnFagBnAQAFAAkJAAnFagBnAQAAAA==.',
St='Stalon:BAAALgADCgYJDgAAAA==.Strangeluve:BAAALgAECgcJEQAAAA==.',
Su='Suerte:BAAALgADCggJDQAAAA==.Suzieq:BAAALgADCgMJBgAAAA==.',
Sy='Sysnootles:BAAALgADCgYJBwAAAA==.',
['Sà']='Sàyori:BAAALgAECgUJBwAAAA==.',
Ta='Tabrett:BAAALgAECgIJAgAAAA==.Talashara:BAAALgADCgEJAQAAAA==.Talashea:BAAALgAECgEJBAAAAA==.Tankdezoe:BAAALgAECgMJBAABLgAECggJEwAOAAAAAA==.Tarall:BAAALgAECgEJAQAAAA==.Taveres:BAAALgADCgEJAQAAAA==.Tax:BAABLgAECn89AAITAAgJJQk2AwDoAAATAAgJJQk2AwDoAAAAAA==.',
Te='Tenara:BAAALgADCgkJEgAAAA==.Tequ:BAAALgAECgMJCQAAAA==.',
Ti='Tiche:BAAALgAFFAEJAQABLgAFFAIJBQAIAD8UAA==.Tim:BAABLgAFFH8GAAIXAAMJ0RbVSwDDAAAXAAMJ0RbVSwDDAAAAAA==.Timeshade:BAAALgAECgUJBwAAAA==.Timeshadow:BAABLgAECn8fAAMfAAYJoQO5QADCAAAfAAYJhwO5QADCAAAeAAEJxgNkBgAeAAAAAA==.Tinakoffee:BAAALgAECgIJAgAAAA==.Tine:BAABLgAECn8oAAIWAAkJixcsRQALAgAWAAkJixcsRQALAgAAAA==.',
To='Tope:BAAALgAECgYJCwAAAA==.Toray:BAABLgAECn8iAAIQAAgJbBNnagCaAQAQAAgJbBNnagCaAQAAAA==.',
Tr='Triplesix:BAABLgAECn8ZAAMnAAkJLBKrKAA3AQAnAAkJLBKrKAA3AQANAAcJ8AS+sgDDAAAAAA==.Trittia:BAABLgAECn88AAMcAAkJ9xT/AgCbAQAcAAkJSxT/AgCbAQAPAAUJfA56BADTAAAAAA==.',
Tu='Tukk:BAABLgAECn8VAAMPAAcJGxI3HwA5AQAPAAcJ4hE3HwA5AQAbAAEJwArdgQAoAAAAAA==.Turtle:BAAALgAECgEJBQAAAA==.',
Tw='Twigatron:BAABLgAECn8VAAILAAgJCBUYLwDoAQALAAgJCBUYLwDoAQABLgAECgcJEQAOAAAAAA==.Twigdin:BAAALgADCgMJAwAAAA==.Twigdun:BAAALgAECgMJBgAAAA==.',
Ty='Tynk:BAAALgAECggJEQAAAA==.',
Ur='Urza:BAAALgAECgYJCgAAAA==.',
Va='Vaewind:BAAALgADCgMJAwAAAA==.Valethus:BAABLgAECn81AAMdAAkJVR2DFgChAgAdAAkJVR2DFgChAgAEAAIJVAgefgBNAAAAAA==.Valmaru:BAAALgADCgkJCQAAAA==.',
Ve='Vesp:BAAALgAECgQJBQAAAA==.Vexxa:BAABLgAECn8YAAINAAkJPBgASwClAQANAAkJPBgASwClAQAAAA==.',
Vi='Viridania:BAAALgAECgUJEAAAAA==.',
Vy='Vynd:BAAALgADCgkJDgABLgAECgYJBgAOAAAAAA==.',
Wa='Walkz:BAABLgAECn8VAAIPAAYJ/B1vAgBYAQAPAAYJ/B1vAgBYAQABLgAECgkJFQACAFwLAA==.Warrockhealz:BAAALgADCgYJBgAAAA==.',
Wi='Wickedlight:BAABLgAECn9BAAIRAAkJhCAJBgDyAgARAAkJhCAJBgDyAgAAAA==.Wickedlock:BAAALgAECgQJCQAAAA==.Wiggleston:BAACLgAFFH8FAAIIAAIJPxT0NwCNAAAIAAIJPxT0NwCNAAAuAAQKfywABAgACQluEmkgAAACAAgACQluEmkgAAACABAAAwljA4tKAWMAABIAAQlkAEgRAA8AAAAA.Willscarlet:BAABLgAECn8WAAIdAAcJFAVzpQD3AAAdAAcJFAVzpQD3AAAAAA==.',
Wo='Wollybully:BAAALgADCgQJBwABLgAECgYJGQASAAMMAA==.',
Wy='Wylethia:BAAALgAECgQJBAAAAA==.',
Xa='Xandris:BAAALgAECgEJAgABLgAECgkJHQAHAMIOAA==.',
Yf='Yffre:BAAALgAECgYJBgAAAA==.',
Yh='Yhana:BAAALgADCggJEwAAAA==.',
Yo='Yolifeismine:BAAALgAECgUJBQAAAA==.Yozsh:BAAALgAECgYJBgAAAA==.',
Za='Zanthiava:BAAALgAECgYJBwAAAA==.Zarathia:BAABLgAECn8ZAAInAAcJfAqjMgD4AAAnAAcJfAqjMgD4AAAAAA==.Zargar:BAAALgAECgEJAQAAAA==.Zaritym:BAABLgAECn8jAAMKAAkJJho2HQAuAgAKAAkJJho2HQAuAgAmAAQJbw8EDgBaAAAAAA==.Zarrilin:BAABLgAECn8oAAIWAAkJlBcpRQAMAgAWAAkJlBcpRQAMAgAAAA==.',
Ze='Zebop:BAAALgAECgEJAgAAAA==.Zeeley:BAAALgADCgYJCgAAAA==.Zelsada:BAAALgAECgEJAQAAAA==.',
Zi='Zibetha:BAACLgAFFH8VAAIGAAYJVBAXBAB2AQAGAAYJVBAXBAB2AQAuAAQKf1EAAgYACQnoHwoCAKoCAAYACQnoHwoCAKoCAAAA.',
Zo='Zoeheals:BAAALgAECggJEwAAAA==.',
Zu='Zuggtmoy:BAAALgADCgkJCgAAAA==.Zulmahn:BAABLgAECn8oAAMXAAkJ5xCzTQB6AQAXAAkJ5xCzTQB6AQAVAAgJYQPwbQCfAAAAAA==.',
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
