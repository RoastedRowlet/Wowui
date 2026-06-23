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

local lookup = {'DeathKnight-Frost','DeathKnight-Blood','Shaman-Enhancement','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Paladin-Holy','Priest-Holy','Monk-Mistweaver','Druid-Restoration','Druid-Balance','DemonHunter-Devourer','Unknown-Unknown','Warrior-Protection','Paladin-Retribution','Monk-Brewmaster','Priest-Shadow','Paladin-Protection','Warlock-Affliction','Hunter-Survival','Shaman-Elemental','Mage-Frost','Shaman-Restoration','Priest-Discipline','Evoker-Augmentation','Evoker-Preservation','Warrior-Arms','Warrior-Fury','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','Mage-Arcane','DemonHunter-Vengeance','Rogue-Outlaw','Druid-Feral','Mage-Fire','Monk-Windwalker','DemonHunter-Havoc',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=46,date='2026-06-21',data={Ab='Absolver:BAAALgADCgYJCwAAAA==.',
Ad='Adabisi:BAAALgADCgQJCQAAAA==.Addu:BAAALgAECgUJBQAAAA==.Adiforis:BAABLgAECn8fAAMBAAkJAQ8YDAC2AQABAAkJfA4YDAC2AQACAAUJawrfPACdAAAAAA==.Adobo:BAABLgAFFH8IAAIDAAQJngeFDAD6AAADAAQJngeFDAD6AAAAAA==.Adventures:BAAALgADCgIJAgAAAA==.',
Ae='Aeralina:BAABLgAECn8XAAIEAAgJpQmrFAAYAQAEAAgJpQmrFAAYAQAAAA==.Aerandir:BAABLgAECn8UAAMFAAYJNQrjrwD5AAAFAAYJNQrjrwD5AAAGAAEJAAAXeQAqAAABLgAECggJGQAHAMoNAA==.Aerwyn:BAAALgAECgYJBgAAAA==.',
Ah='Ahmyra:BAAALgAECgcJEwAAAA==.',
Al='Alessar:BAAALgAECgYJDAAAAA==.Allysson:BAABLgAECn84AAIBAAkJMRTMCQDmAQABAAkJMRTMCQDmAQAAAA==.Alrekur:BAAALgAECgIJAgAAAA==.Alyestra:BAABLgAECn8VAAIIAAgJmhAZLgClAQAIAAgJmhAZLgClAQAAAA==.',
Am='Ambien:BAAALgAECgYJCwAAAA==.',
An='Anibundance:BAAALgAECgcJDAABLgAECgkJLQAJAJ0iAA==.Animyst:BAACLgAFFH8JAAIKAAQJ8hx1JgA6AQAKAAQJ8hx1JgA6AQAuAAQKf0UAAgoACQlMJG4DAIQDAAoACQlMJG4DAIQDAAEuAAQKCQktAAkAnSIA.Anipaltu:BAACLgAFFH8IAAIIAAQJsAw1KQDcAAAIAAQJsAw1KQDcAAAuAAQKfx4AAggACQm2HQcJAPoCAAgACQm2HQcJAPoCAAEuAAQKCQktAAkAnSIA.Aniron:BAABLgAECn8UAAIFAAYJchEgjQAgAQAFAAYJchEgjQAgAQABLgAECgkJLQAJAJ0iAA==.Anirot:BAABLgAECn8tAAIJAAkJnSKTBAA3AwAJAAkJnSKTBAA3AwAAAA==.Anithwip:BAAALgAECgYJBgABLgAECgkJLQAJAJ0iAA==.Antoni:BAAALgAECgEJAQAAAA==.',
Ap='Aphirym:BAAALgAECgIJAgAAAA==.',
Ar='Aranta:BAABLgAECn8aAAMLAAYJmQ41YQASAQALAAYJmQ41YQASAQAMAAYJ9AlGUQDJAAAAAA==.Arcanium:BAAALgAECgEJAgAAAA==.',
As='Astren:BAAALgAECgYJBwAAAA==.Asynsia:BAABLgAECn8oAAINAAkJZiG3EAC8AgANAAkJZiG3EAC8AgAAAA==.',
Av='Avamani:BAAALgADCgkJCQAAAA==.',
Az='Azulmoon:BAAALgAECgYJCwAAAA==.',
Ba='Balrogg:BAAALgADCgcJBwAAAA==.Bartholomew:BAACLgAFFH8GAAIKAAQJVRBfMwDgAAAKAAQJVRBfMwDgAAAuAAQKfy4AAgoACQmmHNwLANsCAAoACQmmHNwLANsCAAAA.Bartno:BAAALgAECgIJAQAAAA==.',
Be='Beefed:BAAALgADCgIJAgAAAA==.Bellathrix:BAAALgAECgMJAwAAAA==.Bessie:BAAALgADCgIJAgAAAA==.',
Bi='Bienfaiseur:BAABLgAECn9BAAIJAAkJmSU2AQC2AwAJAAkJmSU2AQC2AwAAAA==.Bigtonka:BAAALgADCgYJBgAAAA==.',
Bl='Bladez:BAAALgAECgYJBwAAAA==.',
Bo='Boffadeez:BAAALgAECgcJDAAAAA==.Boombawks:BAAALgADCgUJBQABLgAECgEJAgAOAAAAAA==.Boryndin:BAABLgAECn8iAAIPAAkJohkvDgAIAgAPAAkJohkvDgAIAgAAAA==.',
Br='Brad:BAAALgADCgIJAgAAAA==.Breadburn:BAAALgADCggJCAAAAA==.Breezybb:BAACLgAFFH8NAAIQAAUJaREeSAAcAQAQAAUJaREeSAAcAQAuAAQKfzsAAhAACQlhHCw6ADoCABAACQlhHCw6ADoCAAAA.Brewfist:BAAALgADCgUJCAAAAA==.',
Bu='Bulgrim:BAAALgADCggJEQAAAA==.',
Ca='Camhawk:BAAALgADCgkJCQAAAA==.Catastrophe:BAAALgAECgcJBwABLgAECgkJLAARALEPAA==.',
Ce='Cearylin:BAAALgADCgcJEwAAAA==.Cering:BAAALgAECgYJBgAAAA==.',
Ch='Changsauce:BAAALgAECgYJDAAAAA==.Cherypoptart:BAABLgAECn8fAAISAAgJnSNVCQC5AgASAAgJnSNVCQC5AgAAAA==.Chrismeister:BAABLgAECn8ZAAQTAAYJAwwsAwBmAAATAAUJLQssAwBmAAAIAAEJygtIlAArAAAQAAEJAABs2gEAAAAAAA==.',
Ci='Cing:BAAALgAECgEJAQAAAA==.',
Cl='Claymordon:BAAALgADCgYJBgAAAA==.Clothpally:BAAALgAFFAEJAQAAAA==.',
Co='Codah:BAAALgAECgQJDgAAAA==.Contradict:BAAALgAECgEJAQABLgAECgkJLgAQAKYdAA==.Coomonka:BAAALgADCgcJCQAAAA==.Coraggioso:BAAALgADCgYJBgAAAA==.Corbenik:BAAALgAECgIJBgABLgAECgcJGAAFAPEHAA==.',
Cr='Creel:BAAALgADCgYJBgAAAA==.Crethasmus:BAAALgAECgYJCAAAAA==.Crettephal:BAEBLgAECn8aAAIUAAUJYxSdFgAUAQAUAAUJYxSdFgAUAQAAAA==.Crodo:BAAALgADCgYJBgAAAA==.Cruella:BAAALgADCgEJAQAAAA==.',
['Cä']='Cähira:BAAALgAECgMJAwAAAA==.',
Da='Daellan:BAAALgAECgUJCQAAAA==.Dainaira:BAABLgAECn8WAAISAAkJAAg0AwCxAAASAAkJAAg0AwCxAAAAAA==.Daisia:BAABLgAECn8fAAIVAAkJcQa0JQBvAQAVAAkJcQa0JQBvAQAAAA==.Dalarrong:BAAALgAECgMJAwAAAA==.Dasteaire:BAAALgAECgMJBgAAAA==.',
De='Deathdealler:BAABLgAECn8VAAMHAAgJvgL1+QC0AAAHAAgJewL1+QC0AAACAAUJ+wGkUABSAAAAAA==.Deathstopper:BAAALgAECgEJAQABLgAECgkJKAAIALsQAA==.Demonicadhd:BAAALgAECgYJEwAAAA==.Demonsmind:BAABLgAECn8ZAAMFAAgJphE7egBFAQAFAAcJwBA7egBFAQAGAAMJqhEuQQCwAAAAAA==.Derien:BAABLgAECn8mAAIPAAgJQRgkEgDIAQAPAAgJQRgkEgDIAQAAAA==.Derienfu:BAAALgAECgYJBgAAAA==.Devour:BAAALgAFFAEJAQAAAA==.Dezin:BAAALgAECgYJBgAAAA==.',
Di='Dinkeldorf:BAAALgAECgMJBAABLgAFFAIJAgAOAAAAAA==.',
Dk='Dkerien:BAAALgAECggJCAAAAA==.',
Do='Donkeyteeth:BAABLgAECn8kAAIWAAkJag/BLgCGAQAWAAkJag/BLgCGAQAAAA==.Downtownbuu:BAAALgADCgcJDAAAAA==.',
Dr='Dracarian:BAAALgADCgMJAwAAAA==.Dracorz:BAAALgAECgYJCwAAAA==.Dru:BAAALgADCgcJBwAAAA==.Drywater:BAABLgAECn8zAAIXAAgJvRGZbACiAQAXAAgJvRGZbACiAQAAAA==.',
Du='Duck:BAAALgAECgQJBAAAAA==.Dura:BAABLgAECn83AAIYAAkJnRZqAQCpAQAYAAkJnRZqAQCpAQAAAA==.',
El='Eldermoon:BAAALgAECgEJAQAAAA==.Eldunari:BAAALgAECgQJBAAAAA==.Elfblood:BAABLgAECn9HAAIGAAkJcgxtDwBJAQAGAAkJcgxtDwBJAQAAAA==.Elvion:BAAALgAECgMJBQAAAA==.',
Em='Emollama:BAABLgAECn9EAAMHAAkJyg0DVwDAAQAHAAkJyg0DVwDAAQACAAEJJwJpTQAcAAAAAA==.',
En='Engine:BAAALgADCgQJBAAAAA==.',
Ep='Ephimyra:BAAALgAECgQJCAAAAA==.',
Er='Erazer:BAAALgADCgMJAwAAAA==.Erilana:BAAALgAECgYJCgABLgAECgUJCwAOAAAAAA==.',
Et='Etiimasi:BAAALgADCgYJBwAAAA==.',
Ez='Ezanot:BAAALgADCgYJBgAAAA==.',
['Eï']='Eïr:BAAALgAECgQJCAABLgAFFAIJAgAOAAAAAA==.',
Fa='Fabulosa:BAABLgAECn8tAAQSAAgJtAw/MgBSAQASAAgJtAw/MgBSAQAZAAYJ2wnjLwAhAQAJAAUJYAqsVgCBAAAAAA==.Faith:BAABLgAECn8hAAIQAAgJexu5dACEAQAQAAgJexu5dACEAQAAAA==.',
Fi='Finiquito:BAAALgADCgMJAwAAAA==.Finite:BAAALgAECgYJBwABLgAECgkJLgAQAKYdAA==.Firebug:BAABLgAECn8aAAIPAAcJDgeOLQDPAAAPAAcJDgeOLQDPAAAAAA==.',
Fn='Fndruid:BAAALgADCgEJAQAAAA==.Fnmage:BAAALgAECgQJCwAAAA==.Fnshaman:BAAALgAECgQJBAAAAA==.',
Fr='Frieren:BAAALgAECgMJAwABLgAFFAYJIQAaAEYjAA==.',
Fu='Furnok:BAABLgAECn9BAAMWAAkJ3xZ+FwApAgAWAAkJ3xZ+FwApAgAYAAcJMw0IZgApAQAAAA==.Fuzzyshukk:BAAALgAECgcJDgAAAA==.',
Ga='Galethia:BAAALgADCgkJJgAAAA==.Garli:BAAALgADCgMJAwAAAA==.',
Ge='Gerkin:BAAALgADCgcJDwAAAA==.',
Gg='Ggcthulhu:BAAALgAECgMJBQABLgAFFAQJBwAbAJ8IAA==.',
Gh='Ghutz:BAACLgAFFH8TAAIcAAQJxwzUHgD8AAAcAAQJxwzUHgD8AAAuAAQKfzoAAxwACQm6F+gNAAsCABwACQm6F+gNAAsCAB0ABwmICzZIAIMBAAAA.',
Gl='Glitterhoof:BAABLgAECn8gAAIIAAkJjxk2GABGAgAIAAkJjxk2GABGAgAAAA==.Glorblariirn:BAAALgADCgYJBgAAAA==.',
Go='Goliath:BAAALgAECgUJCwAAAA==.Gonja:BAAALgADCgcJFQAAAA==.',
Gr='Grimbjorne:BAAALgADCgcJBwAAAA==.Grimmbeardd:BAAALgADCgYJCgAAAA==.',
Gu='Gumbercules:BAABLgAECn9HAAIbAAkJahOVDAAMAgAbAAkJahOVDAAMAgAAAA==.',
Ha='Hammie:BAAALgADCgkJCQAAAA==.',
He='Hearthglen:BAABLgAECn8gAAIQAAkJnBJoXAC5AQAQAAkJnBJoXAC5AQAAAA==.',
Ho='Hollet:BAABLgAECn8tAAIeAAYJoxHnBAAWAQAeAAYJoxHnBAAWAQAAAA==.Holyblasto:BAAALgADCgEJAQAAAA==.Holyshukk:BAACLgAFFH8TAAIIAAYJVBywCgALAgAIAAYJVBywCgALAgAuAAQKfycAAwgACQmRIqEFABIDAAgACQmRIqEFABIDABAAAQlCBwGzASgAAAEuAAQKBwkOAA4AAAAA.',
Hu='Huckk:BAAALgAECgMJAwAAAA==.',
Hy='Hylen:BAABLgAECn8XAAIUAAkJ7RWkDgBxAQAUAAkJ7RWkDgBxAQAAAA==.',
Ib='Ibrandul:BAABLgAECn86AAIQAAgJ2xZ9TADhAQAQAAgJ2xZ9TADhAQAAAA==.',
Ic='Icyveins:BAABLgAECn8UAAIXAAcJ8wEtDAGaAAAXAAcJ8wEtDAGaAAAAAA==.',
Ir='Iroha:BAAALgADCgQJBgAAAA==.Ironhuntress:BAABLgAECn8jAAIeAAkJgBHtAgBzAQAeAAkJgBHtAgBzAQAAAA==.',
It='Ithro:BAABLgAECn8oAAIfAAkJJxiGBQAeAgAfAAkJJxiGBQAeAgAAAA==.',
Iy='Iyachtu:BAAALgAECgkJEwAAAA==.',
Ja='Jarlo:BAABLgAECn9HAAIfAAkJ1xtfAwCAAgAfAAkJ1xtfAwCAAgAAAA==.',
Je='Jeffeory:BAAALgAECgIJAgABLgAECgkJLQAQAMUaAA==.Jefficiently:BAAALgAECgcJDQABLgAECgkJLQAQAMUaAA==.Jefriel:BAAALgAECgYJBgABLgAECgkJLQAQAMUaAA==.Jezzi:BAAALgAECgMJAwAAAA==.',
Jo='Jobu:BAAALgAECgEJAgAAAA==.Jormungandr:BAABLgAECn8uAAMcAAkJFSJeBQC1AgAcAAkJ1CFeBQC1AgAPAAcJSRmoEgDBAQAAAA==.',
Ju='Juanhunglow:BAAALgAECgMJBAAAAA==.Judgederien:BAAALgAECgIJAgAAAA==.Jularity:BAAALgADCgYJBgAAAA==.',
Ka='Kaeldric:BAABLgAECn81AAMHAAkJ4yLUAABpAgAHAAkJ4yLUAABpAgACAAEJ/w9TYQAnAAAAAA==.Kaladïn:BAAALgAECgEJAQAAAA==.Kalemshai:BAAALgADCgcJCwAAAA==.Kalinea:BAABLgAECn81AAIeAAcJUxSldABWAQAeAAcJUxSldABWAQAAAA==.Karyia:BAAALgAECgUJBQAAAA==.Kazuha:BAAALgAECgYJDgAAAA==.',
Ke='Kellerun:BAAALgADCgIJAgAAAA==.Keruptadin:BAAALgAECgUJBgAAAA==.Ketosis:BAAALgADCggJCgAAAA==.',
Ki='Kintha:BAAALgAECgYJBgAAAA==.',
Ko='Kope:BAABLgAECn8rAAIbAAkJ/BoTBgCpAgAbAAkJ/BoTBgCpAgAAAA==.',
Kr='Kreltor:BAABLgAECn8vAAIYAAkJoSKYAABlAgAYAAkJoSKYAABlAgAAAA==.Kryptikz:BAABLgAECn8UAAMCAAkJXAsRJgAjAQACAAkJnQkRJgAjAQAHAAQJVhA05QC1AAAAAA==.Krystoferson:BAABLgAECn8hAAIgAAgJUwK0OADuAAAgAAgJUwK0OADuAAAAAA==.',
La='Lalatína:BAAALgAECgEJAQAAAA==.Largar:BAAALgADCgUJCAAAAA==.',
Le='Leerroyy:BAAALgADCgIJAgAAAA==.Leesoftpaw:BAAALgADCgYJAgABLgAECgEJAgAOAAAAAA==.Leianii:BAABLgAECn8UAAIVAAgJ6AFTQgC6AAAVAAgJ6AFTQgC6AAAAAA==.Lextali:BAAALgAECgQJBAAAAA==.',
Lh='Lhondar:BAAALgAECgQJBAAAAA==.',
Li='Liafail:BAABLgAECn8YAAIFAAcJ8QesgwBTAQAFAAcJ8QesgwBTAQAAAA==.Lillat:BAABLgAECn8XAAIJAAcJTg7LMgA+AQAJAAcJTg7LMgA+AQAAAA==.Lin:BAAALgAECgEJAQAAAA==.Liryv:BAAALgADCgYJFAAAAA==.Littlepop:BAAALgADCgEJAQAAAA==.',
Lo='Lollilock:BAAALgAECgcJBAAAAA==.',
Lu='Luena:BAAALgAECgYJEgAAAA==.Lugglugg:BAAALgAECgQJBAAAAA==.Lumbre:BAAALgADCgcJCQAAAA==.Luminara:BAAALgAECgcJCwAAAA==.Luuggork:BAAALgAECgMJBAAAAA==.',
Ly='Lyarith:BAAALgAECgMJAwAAAA==.Lyrà:BAAALgAECgQJAwAAAA==.',
['Lá']='Ládydèath:BAAALgAECgYJBwAAAA==.',
['Lì']='Lìesson:BAABLgAECn8zAAIQAAkJiCEPEQDeAgAQAAkJiCEPEQDeAgAAAA==.',
Ma='Mabo:BAAALgAECgEJAQAAAA==.Mackaroni:BAACLgAFFH8HAAIXAAQJWhBoaAATAQAXAAQJWhBoaAATAQAuAAQKfx4AAxcACQnhFyljALgBABcACAlSFiljALgBACEAAwlMFrsAAJsAAAEuAAUUAgkCAA4AAAAA.Madolynne:BAAALgADCgIJAgAAAA==.Madrel:BAAALgADCgUJBQAAAA==.Magesca:BAABLgAECn9MAAIXAAkJrxo/KQB1AgAXAAkJrxo/KQB1AgAAAA==.Magimiester:BAAALgADCgEJAQABLgAECgYJGQATAAMMAA==.Mahalath:BAAALgADCgMJAwAAAA==.Makkagg:BAACLgAFFH8WAAMPAAQJDBoRAwDFAAAPAAQJvRkRAwDFAAAdAAIJkBIJQwCVAAAuAAQKfzUAAw8ACQkiIUYFAMYCAA8ACQkiIUYFAMYCAB0ACAlWDMc5AL8BAAAA.Malamur:BAAALgADCggJEgAAAA==.Malisea:BAABLgAECn8lAAIXAAkJswhieQCGAQAXAAkJswhieQCGAQAAAA==.',
Me='Melarndra:BAAALgADCgYJBgAAAA==.Melynea:BAAALgADCgEJAQAAAA==.',
Mi='Milagrosa:BAABLgAECn8jAAIaAAkJJQ1rLwB7AQAaAAkJJQ1rLwB7AQAAAA==.Mirael:BAACLgAFFH8RAAIeAAYJqRg4HwCHAQAeAAYJqRg4HwCHAQAuAAQKfzgAAh4ACQnQIQEBAFACAB4ACQnQIQEBAFACAAAA.Mishuntsalot:BAAALgAECgEJAQABLgAECgMJAwAOAAAAAA==.',
Mo='Molocherx:BAAALgADCgMJAwAAAA==.Mommacoo:BAABLgAECn8hAAIQAAYJaAo22ADoAAAQAAYJaAo22ADoAAAAAA==.Mori:BAAALgAECgEJAQAAAA==.',
Mu='Mumsms:BAAALgAECgkJBgAAAA==.Mumsurprise:BAAALgAECgkJAgAAAA==.',
My='Myrmia:BAABLgAECn8aAAILAAcJvg1mWAAvAQALAAcJvg1mWAAvAQAAAA==.Mystfang:BAABLgAECn8cAAIXAAkJihT4BAAKAQAXAAkJihT4BAAKAQAAAA==.',
['Mà']='Màck:BAAALgAFFAIJAgAAAA==.',
Na='Nade:BAAALgAECgcJBAAAAA==.Nargul:BAABLgAECn8vAAIFAAcJbRv3QADZAQAFAAcJbRv3QADZAQAAAA==.Naturboom:BAAALgAECgEJAQAAAA==.',
Ne='Nekossian:BAAALgAECgYJCwABLgAECgkJLQAQAMUaAA==.',
Ni='Nickorvis:BAAALgADCgUJBQABLgAECgcJGAAFAPEHAA==.Nirazen:BAAALgAECgIJAgAAAA==.',
No='Nonae:BAEALgADCgYJBgAAAA==.Nota:BAABLgAECn8fAAIQAAkJBwdvBwC/AAAQAAkJBwdvBwC/AAAAAA==.',
Oa='Oathmere:BAAALgAECgMJAwAAAA==.',
Og='Ogrusao:BAABLgAECn8nAAIeAAkJtw1mAwBUAQAeAAkJtw1mAwBUAQAAAA==.Ogun:BAAALgADCgcJCgAAAA==.',
Pa='Panasaurus:BAABLgAECn9HAAIiAAkJ0RVfCADuAQAiAAkJ0RVfCADuAQAAAA==.',
Pe='Pechuuga:BAABLgAECn8WAAIRAAcJwBmCMgCHAQARAAcJwBmCMgCHAQAAAA==.Pelli:BAABLgAECn81AAISAAkJlQl+AQAzAQASAAkJlQl+AQAzAQAAAA==.Pendraig:BAAALgAECgYJCwAAAA==.Pestilense:BAAALgADCgIJAgAAAA==.',
Pl='Plaza:BAAALgAECgkJEwAAAA==.',
Qu='Quadrilio:BAAALgADCgUJBQAAAA==.Quamutei:BAAALgADCgUJBgAAAA==.',
Ra='Raylisarri:BAAALgAECgEJAgABLgAECgUJFAAGAPAIAA==.Rayst:BAABLgAECn8tAAIXAAgJLQSzCwB1AAAXAAgJLQSzCwB1AAAAAA==.Razìel:BAAALgADCgMJAgAAAA==.',
Rh='Rhalek:BAACLgAFFH8GAAILAAMJhxL1QQCqAAALAAMJhxL1QQCqAAAuAAQKfx8AAgsACAkJIesMAPYCAAsACAkJIesMAPYCAAAA.Rheunae:BAAALgAECgQJBAAAAA==.Rhykis:BAABLgAECn8kAAMdAAkJMCOICQDKAgAdAAkJiiKICQDKAgAPAAMJcBpVAQD0AAAAAA==.',
Ri='Rilis:BAAALgADCgEJAQAAAA==.Rillyn:BAABLgAECn86AAMVAAkJKhdGDwA5AgAVAAkJxhZGDwA5AgAeAAEJ+hRMJAE7AAAAAA==.',
Ro='Rojei:BAAALgADCgYJBgAAAA==.Role:BAAALgADCgEJAQABLgAECggJLgAjAGUZAA==.',
Ru='Rubbin:BAAALgAECgEJAQAAAA==.',
Sa='Sabba:BAAALgADCgYJBgAAAA==.Sagearian:BAAALgAECgYJDgAAAA==.Salindill:BAAALgADCgMJAwAAAA==.Salline:BAABLgAECn8kAAMeAAgJAwhPjgAiAQAeAAgJ+gdPjgAiAQAVAAQJfALwVABaAAAAAA==.Samanda:BAABLgAECn8hAAIkAAcJ7RPSFQBrAQAkAAcJ7RPSFQBrAQAAAA==.Samshir:BAABLgAECn8ZAAIHAAgJyg1MdwB1AQAHAAgJyg1MdwB1AQAAAA==.',
Sc='Scorned:BAABLgAECn8zAAINAAgJBBMMUACVAQANAAgJBBMMUACVAQAAAA==.',
Se='Sekrain:BAAALgAECgQJBAAAAA==.Seosinz:BAABLgAECn8bAAIMAAYJ5BKyPAAeAQAMAAYJ5BKyPAAeAQAAAA==.',
Sh='Shadowmane:BAAALgAECgEJAQAAAA==.Shamnasty:BAAALgAECgcJEwAAAA==.Shariaan:BAAALgAECgYJCQAAAA==.Shaylinn:BAAALgAECgMJBgAAAA==.Shenanigan:BAAALgADCgEJAQABLgAECgkJLgAQAKYdAA==.Shukkvoker:BAAALgADCgQJBQABLgAECgcJDgAOAAAAAA==.Shùkkle:BAAALgAECgEJAQAAAA==.',
Si='Siella:BAABLgAECn83AAIJAAkJrxKvAQAnAQAJAAkJrxKvAQAnAQAAAA==.Sileves:BAAALgAECgEJAgABLgAECgUJCwAOAAAAAA==.Sitrom:BAAALgAECgUJCwAAAA==.',
Sn='Snayd:BAABLgAECn8yAAMXAAkJSCHjHwCfAgAXAAgJfiHjHwCfAgAlAAcJMhgrAAB6AQAAAA==.Snowette:BAAALgADCgIJAgAAAA==.',
So='Solar:BAAALgAFFAIJAgAAAA==.Somenai:BAAALgAECgQJBQAAAA==.Sonofmums:BAAALgAECgkJBgAAAA==.Sora:BAAALgAECgEJAQAAAA==.Soulbaine:BAABLgAECn8aAAMCAAcJuBbqGgCGAQACAAcJuBbqGgCGAQAHAAQJRhLd8QC+AAAAAA==.',
Sp='Spazeric:BAABLgAECn8oAAQKAAkJzxRmHwAfAgAKAAkJzxRmHwAfAgAmAAcJKBavMwA1AQARAAQJrQbHAQC6AAAAAA==.Spheria:BAABLgAECn8/AAIFAAkJAAn9BACzAAAFAAkJAAn9BACzAAAAAA==.',
St='Stalon:BAAALgADCgYJDgAAAA==.Strangeluve:BAAALgAECgcJEQAAAA==.',
Su='Suerte:BAAALgADCggJDQAAAA==.Suzieq:BAAALgADCgMJBgAAAA==.',
Sy='Sysnootles:BAAALgADCgYJBwAAAA==.',
['Sà']='Sàyori:BAAALgAECgUJBwAAAA==.',
Ta='Tabrett:BAAALgAECgIJAgAAAA==.Talashara:BAAALgADCgEJAQAAAA==.Talashea:BAAALgAECgEJBAAAAA==.Tankdezoe:BAAALgAECgMJBAABLgAECggJEwAOAAAAAA==.Tarall:BAAALgAECgEJAQAAAA==.Taveres:BAAALgADCgEJAQAAAA==.Tax:BAABLgAECn8rAAIUAAgJNwjxFQAbAQAUAAgJNwjxFQAbAQAAAA==.',
Te='Tenara:BAAALgADCgkJEgAAAA==.Tequ:BAAALgAECgMJBgAAAA==.',
Ti='Tiche:BAAALgAECgEJAwABLgAECgkJKAAIALsQAA==.Tim:BAABLgAFFH8FAAIYAAMJ0RbUSwDDAAAYAAMJ0RbUSwDDAAAAAA==.Timeshadow:BAABLgAECn8dAAIgAAYJhwO4QADCAAAgAAYJhwO4QADCAAAAAA==.Tinakoffee:BAAALgAECgIJAgAAAA==.Tine:BAABLgAECn8oAAIXAAkJixcuRQALAgAXAAkJixcuRQALAgAAAA==.',
To='Tope:BAAALgAECgYJCwAAAA==.Toray:BAABLgAECn8iAAIQAAgJbBNmagCaAQAQAAgJbBNmagCaAQAAAA==.',
Tr='Triplesix:BAABLgAECn8XAAMnAAkJpRGoKAA3AQAnAAkJpRGoKAA3AQANAAcJ8AS7sgDDAAAAAA==.Trittia:BAABLgAECn8yAAMPAAgJjxSGAQDVAAAdAAgJoxNHNAB5AQAPAAUJfA6GAQDVAAAAAA==.',
Tu='Tukk:BAABLgAECn8VAAMPAAcJGxI3HwA5AQAPAAcJ4hE3HwA5AQAcAAEJwArdgQAoAAAAAA==.Turtle:BAAALgAECgEJBQAAAA==.',
Tw='Twigatron:BAABLgAECn8VAAILAAgJCBUaLwDoAQALAAgJCBUaLwDoAQABLgAECgcJEQAOAAAAAA==.Twigdin:BAAALgADCgMJAwAAAA==.Twigdun:BAAALgAECgMJBgAAAA==.',
Ty='Tynk:BAAALgAECgUJCgAAAA==.',
Ur='Urza:BAAALgAECgYJCgAAAA==.',
Va='Vaewind:BAAALgADCgMJAwAAAA==.Valethus:BAABLgAECn81AAMeAAkJVR2FFgChAgAeAAkJVR2FFgChAgAEAAIJVAgefgBNAAAAAA==.Valmaru:BAAALgADCgkJCQAAAA==.',
Ve='Vesp:BAAALgAECgQJBQAAAA==.Vexxa:BAABLgAECn8YAAINAAkJPBgBSwClAQANAAkJPBgBSwClAQAAAA==.',
Vi='Viridania:BAAALgAECgUJDwAAAA==.',
Vy='Vynd:BAAALgADCgkJDgABLgAECgYJBgAOAAAAAA==.',
Wa='Walkz:BAABLgAECn8VAAIPAAYJ/B3TAABbAQAPAAYJ/B3TAABbAQABLgAECgkJFAACAFwLAA==.Warrockhealz:BAAALgADCgYJBgAAAA==.',
Wi='Wickedlight:BAABLgAECn9BAAISAAkJrCAJBgDyAgASAAkJrCAJBgDyAgAAAA==.Wickedlock:BAAALgAECgQJCQAAAA==.Wiggleston:BAABLgAECn8oAAQIAAkJuxBqIAAAAgAIAAkJuxBqIAAAAgAQAAMJYwOISgFjAAATAAEJZADJBgAPAAAAAA==.Willscarlet:BAABLgAECn8WAAIeAAcJFAVupQD3AAAeAAcJFAVupQD3AAAAAA==.',
Wo='Wollybully:BAAALgADCgQJBwABLgAECgYJGQATAAMMAA==.',
Wy='Wylethia:BAAALgAECgQJBAAAAA==.',
Xa='Xandris:BAAALgAECgEJAgABLgAECggJGQAHAMoNAA==.',
Yf='Yffre:BAAALgAECgYJBgAAAA==.',
Yh='Yhana:BAAALgADCggJEwAAAA==.',
Yo='Yolifeismine:BAAALgAECgUJBQAAAA==.Yozsh:BAAALgAECgYJBgAAAA==.',
Za='Zanthiava:BAAALgAECgIJAgAAAA==.Zarathia:BAABLgAECn8ZAAInAAcJfAqiMgD4AAAnAAcJfAqiMgD4AAAAAA==.Zaritym:BAABLgAECn8iAAMKAAkJLho3HQAuAgAKAAkJLho3HQAuAgAmAAQJbw9WBABhAAAAAA==.Zarrilin:BAABLgAECn8oAAIXAAkJlBcqRQAMAgAXAAkJlBcqRQAMAgAAAA==.',
Ze='Zebop:BAAALgAECgEJAgAAAA==.Zeeley:BAAALgADCgYJCgAAAA==.Zelsada:BAAALgAECgEJAQAAAA==.',
Zi='Zibetha:BAACLgAFFH8TAAIGAAYJVBAWBAB2AQAGAAYJVBAWBAB2AQAuAAQKf1AAAgYACQnoHwoCAKoCAAYACQnoHwoCAKoCAAAA.',
Zo='Zoeheals:BAAALgAECggJEwAAAA==.',
Zu='Zuggtmoy:BAAALgADCgkJCgAAAA==.Zulmahn:BAABLgAECn8nAAMYAAgJehCwTQB6AQAYAAgJehCwTQB6AQAWAAgJSgPtbQCfAAAAAA==.',
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
