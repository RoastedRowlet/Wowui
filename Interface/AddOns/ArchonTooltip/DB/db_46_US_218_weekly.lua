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

local lookup = {'DeathKnight-Frost','DeathKnight-Blood','Shaman-Enhancement','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Paladin-Holy','Priest-Holy','Monk-Mistweaver','Druid-Restoration','Druid-Balance','DemonHunter-Devourer','Unknown-Unknown','Warrior-Protection','Paladin-Retribution','Monk-Brewmaster','Priest-Shadow','Paladin-Protection','Warlock-Affliction','Hunter-Survival','Shaman-Elemental','Mage-Frost','Shaman-Restoration','Priest-Discipline','Evoker-Augmentation','Evoker-Preservation','Warrior-Arms','Warrior-Fury','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Vengeance','Rogue-Outlaw','Druid-Feral','Mage-Fire','Monk-Windwalker','DemonHunter-Havoc',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=46,date='2026-06-14',data={Ab='Absolver:BAAALgADCgYJCwAAAA==.',
Ad='Adabisi:BAAALgADCgQJBgAAAA==.Addu:BAAALgAECgUJBQAAAA==.Adiforis:BAABLgAECn8dAAMBAAkJgQ5VDwB9AQABAAgJYA5VDwB9AQACAAUJawpAPACeAAAAAA==.Adobo:BAABLgAFFH8HAAIDAAQJnAcQDAD+AAADAAQJnAcQDAD+AAAAAA==.Adventures:BAAALgADCgIJAgAAAA==.',
Ae='Aeralina:BAABLgAECn8XAAIEAAgJpQlsFAAYAQAEAAgJpQlsFAAYAQAAAA==.Aerandir:BAABLgAECn8UAAMFAAYJNQrjrwD5AAAFAAYJNQrjrwD5AAAGAAEJAAAXeQAqAAABLgAECggJGQAHAMoNAA==.Aerwyn:BAAALgAECgYJBgAAAA==.',
Ah='Ahmyra:BAAALgAECgcJEwAAAA==.',
Al='Alessar:BAAALgAECgYJDAAAAA==.Allysson:BAABLgAECn80AAIBAAkJMRSeCQDpAQABAAkJMRSeCQDpAQAAAA==.Alrekur:BAAALgAECgIJAgAAAA==.Alyestra:BAABLgAECn8VAAIIAAgJmhDCLQCmAQAIAAgJmhDCLQCmAQAAAA==.',
Am='Ambien:BAAALgAECgYJCwAAAA==.',
An='Anibundance:BAAALgAECgcJDAABLgAECgkJLQAJAJ0iAA==.Animyst:BAACLgAFFH8JAAIKAAQJ8hzvJAA7AQAKAAQJ8hzvJAA7AQAuAAQKfz8AAgoACQm6I14DAIQDAAoACQm6I14DAIQDAAEuAAQKCQktAAkAnSIA.Anipaltu:BAACLgAFFH8IAAIIAAQJsAyNKADcAAAIAAQJsAyNKADcAAAuAAQKfx4AAggACQm2HeQIAPsCAAgACQm2HeQIAPsCAAEuAAQKCQktAAkAnSIA.Aniron:BAABLgAECn8UAAIFAAYJchHnjAAhAQAFAAYJchHnjAAhAQABLgAECgkJLQAJAJ0iAA==.Anirot:BAABLgAECn8tAAIJAAkJnSJ/BAA4AwAJAAkJnSJ/BAA4AwAAAA==.Anithwip:BAAALgAECgYJBgABLgAECgkJLQAJAJ0iAA==.Antoni:BAAALgAECgEJAQAAAA==.',
Ap='Aphirym:BAAALgAECgIJAgAAAA==.',
Ar='Aranta:BAABLgAECn8aAAMLAAYJmQ6yYAARAQALAAYJmQ6yYAARAQAMAAYJ9AlOUADJAAAAAA==.Arcanium:BAAALgAECgEJAgAAAA==.',
As='Astren:BAAALgAECgEJAQAAAA==.Asynsia:BAABLgAECn8oAAINAAkJZiGLEAC8AgANAAkJZiGLEAC8AgAAAA==.',
Av='Avamani:BAAALgADCgkJCQAAAA==.',
Az='Azulmoon:BAAALgAECgYJCwAAAA==.',
Ba='Balrogg:BAAALgADCgcJBwAAAA==.Bartholomew:BAACLgAFFH8GAAIKAAQJVRDAMQDgAAAKAAQJVRDAMQDgAAAuAAQKfy4AAgoACQmmHKsLANoCAAoACQmmHKsLANoCAAAA.Bartno:BAAALgAECgIJAQAAAA==.',
Be='Beefed:BAAALgADCgIJAgAAAA==.Bellathrix:BAAALgADCgIJAgAAAA==.Bessie:BAAALgADCgIJAgAAAA==.',
Bi='Bienfaiseur:BAABLgAECn89AAIJAAkJYCUuAQC2AwAJAAkJYCUuAQC2AwAAAA==.Bigtonka:BAAALgADCgYJBgAAAA==.',
Bl='Bladez:BAAALgAECgYJBwAAAA==.',
Bo='Boffadeez:BAAALgAECgcJDAAAAA==.Boombawks:BAAALgADCgUJBQABLgAECgEJAgAOAAAAAA==.Boryndin:BAABLgAECn8iAAIPAAkJohn0DQAJAgAPAAkJohn0DQAJAgAAAA==.',
Br='Brad:BAAALgADCgIJAgAAAA==.Breadburn:BAAALgADCggJCAAAAA==.Breezybb:BAACLgAFFH8LAAIQAAQJaQ80SgAVAQAQAAQJaQ80SgAVAQAuAAQKfzoAAhAACQlhHCw6ADoCABAACQlhHCw6ADoCAAAA.Brewfist:BAAALgADCgUJCAAAAA==.',
Bu='Bulgrim:BAAALgADCggJEQAAAA==.',
Ca='Camhawk:BAAALgADCgkJCQAAAA==.Catastrophe:BAAALgAECgcJBwABLgAECgkJLAARALEPAA==.',
Ce='Cearylin:BAAALgADCgcJEwAAAA==.Cering:BAAALgAECgYJBgAAAA==.',
Ch='Changsauce:BAAALgAECgYJDAAAAA==.Cherypoptart:BAABLgAECn8fAAISAAgJnSM4CQC7AgASAAgJnSM4CQC7AgAAAA==.Chrismeister:BAABLgAECn8VAAQTAAYJAwzeMQCbAAATAAUJLQveMQCbAAAIAAEJygsEkwArAAAQAAEJAAA91AEAAAAAAA==.',
Cl='Claymordon:BAAALgADCgYJBgAAAA==.Clothpally:BAAALgAFFAEJAQAAAA==.',
Co='Codah:BAAALgAECgQJDAAAAA==.Coomonka:BAAALgADCgcJCQAAAA==.Coraggioso:BAAALgADCgYJBgAAAA==.Corbenik:BAAALgAECgIJBgABLgAECgcJGAAFAPEHAA==.',
Cr='Creel:BAAALgADCgYJBgAAAA==.Crethasmus:BAAALgAECgYJCAAAAA==.Crettephal:BAEBLgAECn8aAAIUAAUJYxRNFgAUAQAUAAUJYxRNFgAUAQAAAA==.Crodo:BAAALgADCgYJBgAAAA==.Cruella:BAAALgADCgEJAQAAAA==.',
['Cä']='Cähira:BAAALgAECgMJAwAAAA==.',
Da='Daellan:BAAALgAECgUJCQAAAA==.Dainaira:BAAALgAECgkJEAAAAA==.Daisia:BAABLgAECn8cAAIVAAkJcQZ0JQByAQAVAAkJcQZ0JQByAQAAAA==.Dalarrong:BAAALgAECgMJAwAAAA==.Dasteaire:BAAALgAECgMJBgAAAA==.',
De='Deathdealler:BAABLgAECn8VAAMHAAgJvgLx9gC1AAAHAAgJewLx9gC1AAACAAUJ+wHfTwBSAAAAAA==.Deathstopper:BAAALgAECgEJAQAAAA==.Demonicadhd:BAAALgAECgYJEwAAAA==.Demonsmind:BAABLgAECn8ZAAMFAAgJphE2eABJAQAFAAcJwBA2eABJAQAGAAMJqhEuQQCwAAAAAA==.Derien:BAABLgAECn8mAAIPAAgJQRjtEQDIAQAPAAgJQRjtEQDIAQAAAA==.Derienfu:BAAALgAECgYJBgAAAA==.Devour:BAAALgAFFAEJAQAAAA==.Dezin:BAAALgAECgYJBgAAAA==.',
Di='Dinkeldorf:BAAALgAECgMJBAABLgAFFAIJAgAOAAAAAA==.',
Dk='Dkerien:BAAALgAECggJCAAAAA==.',
Do='Donkeyteeth:BAABLgAECn8kAAIWAAkJag8ELgCIAQAWAAkJag8ELgCIAQAAAA==.Downtownbuu:BAAALgADCgcJDAAAAA==.',
Dr='Dracarian:BAAALgADCgMJAwAAAA==.Dracorz:BAAALgAECgYJCwAAAA==.Draqula:BAAALgADCggJEgAAAA==.Dru:BAAALgADCgcJBwAAAA==.Drywater:BAABLgAECn8zAAIXAAgJvRGaawCiAQAXAAgJvRGaawCiAQAAAA==.',
Du='Dura:BAABLgAECn8wAAIYAAgJWBjFIwA1AgAYAAgJWBjFIwA1AgAAAA==.',
El='Eldermoon:BAAALgADCgEJAQAAAA==.Eldunari:BAAALgAECgQJBAAAAA==.Elfblood:BAABLgAECn9DAAIGAAkJTwwzDwBJAQAGAAkJTwwzDwBJAQAAAA==.Elvion:BAAALgAECgMJBQAAAA==.',
Em='Emollama:BAABLgAECn9EAAMHAAkJyg21VQDCAQAHAAkJyg21VQDCAQACAAEJJwJpTQAcAAAAAA==.',
En='Engine:BAAALgADCgQJBAAAAA==.',
Er='Erazer:BAAALgADCgMJAwAAAA==.Erilana:BAAALgAECgEJBAABLgAECgUJCwAOAAAAAA==.',
Et='Etiimasi:BAAALgADCgYJBwAAAA==.',
Ez='Ezanot:BAAALgADCgYJBgAAAA==.',
['Eï']='Eïr:BAAALgAECgQJCAABLgAFFAIJAgAOAAAAAA==.',
Fa='Fabulosa:BAABLgAECn8tAAQSAAgJtAxHMQBXAQASAAgJtAxHMQBXAQAZAAYJ2wnjLwAhAQAJAAUJYArMVQCBAAAAAA==.Faith:BAABLgAECn8fAAIQAAYJlxyUcwCFAQAQAAYJlxyUcwCFAQAAAA==.',
Fi='Finiquito:BAAALgADCgMJAwAAAA==.Finite:BAAALgAECgYJBwABLgAECgkJLgAQAKYdAA==.Firebug:BAABLgAECn8aAAIPAAcJDgciLQDPAAAPAAcJDgciLQDPAAAAAA==.',
Fn='Fndruid:BAAALgADCgEJAQAAAA==.Fnmage:BAAALgAECgQJCwAAAA==.Fnshaman:BAAALgAECgQJBAAAAA==.',
Fr='Frieren:BAAALgAECgMJAwABLgAFFAYJIQAaAEYjAA==.',
Fu='Furnok:BAABLgAECn89AAMWAAkJ3xZDFwApAgAWAAkJ3xZDFwApAgAYAAcJMw3dZAApAQAAAA==.Fuzzyshukk:BAAALgAECgcJDgAAAA==.',
Ga='Galethia:BAAALgADCgkJJgAAAA==.Garli:BAAALgADCgMJAwAAAA==.',
Ge='Gerkin:BAAALgADCgcJDwAAAA==.',
Gg='Ggcthulhu:BAAALgAECgMJBQABLgAFFAQJBwAbAJ8IAA==.',
Gh='Ghutz:BAACLgAFFH8TAAIcAAQJxwz1HQD8AAAcAAQJxwz1HQD8AAAuAAQKfzoAAxwACQm6F7kNAAsCABwACQm6F7kNAAsCAB0ABwmICzZIAIMBAAAA.',
Gl='Glitterhoof:BAABLgAECn8gAAIIAAkJjxn0FwBHAgAIAAkJjxn0FwBHAgAAAA==.Glorblariirn:BAAALgADCgYJBgAAAA==.',
Go='Goliath:BAAALgAECgUJCwAAAA==.Gonja:BAAALgADCgcJFQAAAA==.',
Gr='Grimbjorne:BAAALgADCgcJBwAAAA==.Grimmbeardd:BAAALgADCgYJCgAAAA==.',
Gu='Gumbercules:BAABLgAECn9DAAIbAAkJaRN4DAALAgAbAAkJaRN4DAALAgAAAA==.',
Ha='Hammie:BAAALgADCgkJCQAAAA==.',
He='Hearthglen:BAABLgAECn8cAAIQAAkJWRH8WgC7AQAQAAkJWRH8WgC7AQAAAA==.',
Ho='Hollet:BAABLgAECn8nAAIeAAYJjRBmiQApAQAeAAYJjRBmiQApAQAAAA==.Holyblasto:BAAALgADCgEJAQAAAA==.Holyshukk:BAACLgAFFH8SAAIIAAUJEh96DwC8AQAIAAUJEh96DwC8AQAuAAQKfycAAwgACQmRIqEFABIDAAgACQmRIqEFABIDABAAAQlCByeuASgAAAEuAAQKBwkOAA4AAAAA.',
Hu='Huckk:BAAALgAECgMJAwAAAA==.',
Hy='Hylen:BAABLgAECn8UAAIUAAgJOhRTDgBzAQAUAAgJOhRTDgBzAQAAAA==.',
Ib='Ibrandul:BAABLgAECn86AAIQAAgJ2xbBSwDiAQAQAAgJ2xbBSwDiAQAAAA==.',
Ic='Icyveins:BAABLgAECn8UAAIXAAcJ8wHxCQGaAAAXAAcJ8wHxCQGaAAAAAA==.',
Ir='Iroha:BAAALgADCgQJBgAAAA==.Ironhuntress:BAABLgAECn8cAAIeAAgJ0xDZWgCRAQAeAAgJ0xDZWgCRAQAAAA==.',
It='Ithro:BAABLgAECn8nAAIfAAkJJxh+BQAeAgAfAAkJJxh+BQAeAgAAAA==.',
Iy='Iyachtu:BAAALgAECgkJEwAAAA==.',
Ja='Jarlo:BAABLgAECn9DAAIfAAkJ5BpYAwB/AgAfAAkJ5BpYAwB/AgAAAA==.',
Je='Jeffeory:BAAALgAECgIJAgABLgAECgkJLQAQAMUaAA==.Jefficiently:BAAALgAECgYJBgABLgAECgkJLQAQAMUaAA==.Jefriel:BAAALgAECgYJBgABLgAECgkJLQAQAMUaAA==.',
Jo='Jobu:BAAALgAECgEJAgAAAA==.Jormungandr:BAABLgAECn8uAAMcAAkJFSJKBQC1AgAcAAkJ1CFKBQC1AgAPAAcJSRlqEgDCAQAAAA==.',
Ju='Juanhunglow:BAAALgAECgMJBAAAAA==.Judgederien:BAAALgAECgIJAgAAAA==.Jularity:BAAALgADCgYJBgAAAA==.',
Ka='Kaeldric:BAABLgAECn8uAAMHAAgJ7SGiGwCfAgAHAAgJ7SGiGwCfAgACAAEJ/w8rYAAnAAAAAA==.Kaladïn:BAAALgAECgEJAQAAAA==.Kalemshai:BAAALgADCgcJCwAAAA==.Kalinea:BAABLgAECn81AAIeAAcJUxQ5cwBWAQAeAAcJUxQ5cwBWAQAAAA==.Karyia:BAAALgAECgUJBQAAAA==.Kazuha:BAAALgAECgYJDgAAAA==.',
Ke='Kellerun:BAAALgADCgIJAgAAAA==.Keruptadin:BAAALgAECgUJBgAAAA==.Ketosis:BAAALgADCggJCgAAAA==.',
Ki='Kintha:BAAALgAECgYJBgAAAA==.',
Ko='Kope:BAABLgAECn8rAAIbAAkJ/BoCBgCpAgAbAAkJ/BoCBgCpAgAAAA==.',
Kr='Kreltor:BAABLgAECn8oAAIYAAgJRiKZDQDnAgAYAAgJRiKZDQDnAgAAAA==.Kryptikz:BAAALgAECgkJEgAAAA==.Krystoferson:BAABLgAECn8hAAIgAAgJUwIVOADuAAAgAAgJUwIVOADuAAAAAA==.',
La='Largar:BAAALgADCgUJCAAAAA==.',
Le='Leerroyy:BAAALgADCgIJAgAAAA==.Leesoftpaw:BAAALgADCgYJAgABLgAECgEJAgAOAAAAAA==.Leianii:BAABLgAECn8UAAIVAAgJ6AHIQQC8AAAVAAgJ6AHIQQC8AAAAAA==.Lextali:BAAALgAECgQJBAAAAA==.',
Lh='Lhondar:BAAALgAECgQJBAAAAA==.',
Li='Liafail:BAABLgAECn8YAAIFAAcJ8QesgwBTAQAFAAcJ8QesgwBTAQAAAA==.Lillat:BAABLgAECn8XAAIJAAcJTg46MgA+AQAJAAcJTg46MgA+AQAAAA==.Lin:BAAALgAECgEJAQAAAA==.Liryv:BAAALgADCgYJFAAAAA==.Littlepop:BAAALgADCgEJAQAAAA==.',
Lo='Lollilock:BAAALgAECgcJBAAAAA==.',
Lu='Luena:BAAALgAECgYJEgAAAA==.Lugglugg:BAAALgAECgQJBAAAAA==.Lumbre:BAAALgADCgcJCQAAAA==.Luminara:BAAALgAECgcJCwAAAA==.Luuggork:BAAALgAECgIJAgAAAA==.',
Ly='Lyarith:BAAALgADCgcJBwAAAA==.Lyrà:BAAALgAECgQJAwAAAA==.',
['Lá']='Ládydèath:BAAALgAECgYJBwAAAA==.',
['Lì']='Lìesson:BAABLgAECn8zAAIQAAkJiCGqEADgAgAQAAkJiCGqEADgAgAAAA==.',
Ma='Mabo:BAAALgAECgEJAQAAAA==.Mackaroni:BAACLgAFFH8HAAIXAAQJWhBjZgAdAQAXAAQJWhBjZgAdAQAuAAQKfxoAAhcACAlSFhNiALgBABcACAlSFhNiALgBAAEuAAUUAgkCAA4AAAAA.Madolynne:BAAALgADCgIJAgAAAA==.Madrel:BAAALgADCgUJBQAAAA==.Magesca:BAABLgAECn9IAAIXAAkJrxquKAB2AgAXAAkJrxquKAB2AgAAAA==.Magimiester:BAAALgADCgEJAQABLgAECgYJFQATAAMMAA==.Mahalath:BAAALgADCgMJAwAAAA==.Makkagg:BAACLgAFFH8TAAMPAAQJDBqyEQAWAQAPAAQJvRmyEQAWAQAdAAIJkBKvQQCVAAAuAAQKfzUAAw8ACQkiITEFAMcCAA8ACQkiITEFAMcCAB0ACAlWDMc5AL8BAAAA.Malamur:BAAALgADCggJEgAAAA==.Malisea:BAABLgAECn8kAAIXAAkJswgzeACGAQAXAAkJswgzeACGAQAAAA==.',
Me='Melarndra:BAAALgADCgYJBgAAAA==.',
Mi='Milagrosa:BAABLgAECn8jAAIaAAkJJQ2PLgB+AQAaAAkJJQ2PLgB+AQAAAA==.Mirael:BAACLgAFFH8QAAIeAAUJqxyBOQA1AQAeAAUJqxyBOQA1AQAuAAQKfzEAAh4ACQnKIMAIAAcDAB4ACQnKIMAIAAcDAAAA.Mishuntsalot:BAAALgAECgEJAQABLgAECgMJAwAOAAAAAA==.',
Mo='Molocherx:BAAALgADCgMJAwAAAA==.Mommacoo:BAABLgAECn8hAAIQAAYJaArr1ADrAAAQAAYJaArr1ADrAAAAAA==.Mori:BAAALgAECgEJAQAAAA==.',
Mu='Mumsms:BAAALgAECgkJBgAAAA==.Mumsurprise:BAAALgAECgkJAgAAAA==.',
My='Myrmia:BAABLgAECn8aAAILAAcJvg3wVwAvAQALAAcJvg3wVwAvAQAAAA==.Mystfang:BAABLgAECn8XAAIXAAkJNhNWTgDuAQAXAAkJNhNWTgDuAQAAAA==.',
['Mà']='Màck:BAAALgAFFAIJAgAAAA==.',
Na='Nade:BAAALgAECgcJBAAAAA==.Naldor:BAAALgADCgkJCQAAAA==.Nargul:BAABLgAECn8vAAIFAAcJbRuRQADaAQAFAAcJbRuRQADaAQAAAA==.Naturboom:BAAALgAECgEJAQAAAA==.',
Ne='Nekossian:BAAALgAECgYJCwABLgAECgkJLQAQAMUaAA==.',
Ni='Nickorvis:BAAALgADCgUJBQABLgAECgcJGAAFAPEHAA==.Nirazen:BAAALgAECgIJAgAAAA==.',
No='Nonae:BAEALgADCgYJBgAAAA==.Nota:BAABLgAECn8YAAIQAAcJigdu1gDpAAAQAAcJigdu1gDpAAAAAA==.',
Oa='Oathmere:BAAALgAECgMJAwAAAA==.',
Og='Ogrusao:BAABLgAECn8gAAIeAAgJeA2aXwCFAQAeAAgJeA2aXwCFAQAAAA==.Ogun:BAAALgADCgcJCgAAAA==.',
Pa='Panasaurus:BAABLgAECn9DAAIhAAkJ0RVRCADuAQAhAAkJ0RVRCADuAQAAAA==.',
Pe='Pechuuga:BAABLgAECn8WAAIRAAcJwBmCMgCHAQARAAcJwBmCMgCHAQAAAA==.Pelli:BAABLgAECn8uAAISAAgJYAgQOgApAQASAAgJYAgQOgApAQAAAA==.Pendraig:BAAALgAECgYJCwAAAA==.Pestilense:BAAALgADCgIJAgAAAA==.',
Pl='Plaza:BAAALgAECgkJEwAAAA==.',
Qu='Quadrilio:BAAALgADCgUJBQAAAA==.Quamutei:BAAALgADCgUJBgAAAA==.',
Ra='Raylisarri:BAAALgAECgEJAgABLgAECgUJFAAGAPAIAA==.Rayst:BAABLgAECn8nAAIXAAgJwQIq3ADdAAAXAAgJwQIq3ADdAAAAAA==.Razìel:BAAALgADCgMJAgAAAA==.',
Rh='Rhalek:BAACLgAFFH8GAAILAAMJhxLmQACqAAALAAMJhxLmQACqAAAuAAQKfx8AAgsACAkJIcMMAPYCAAsACAkJIcMMAPYCAAAA.Rheunae:BAAALgAECgQJBAAAAA==.Rhykis:BAABLgAECn8dAAIdAAkJGCFUCQDMAgAdAAkJGCFUCQDMAgAAAA==.',
Ri='Rilis:BAAALgADCgEJAQAAAA==.Rillyn:BAABLgAECn82AAMVAAkJKhfpDgA+AgAVAAkJxhbpDgA+AgAeAAEJ+hTFHwE7AAAAAA==.',
Ro='Rojei:BAAALgADCgYJBgAAAA==.Role:BAAALgADCgEJAQABLgAECggJLgAiAGUZAA==.',
Ru='Rubbin:BAAALgAECgEJAQAAAA==.',
Sa='Sabba:BAAALgADCgYJBgAAAA==.Sagearian:BAAALgAECgUJCAAAAA==.Salindill:BAAALgADCgMJAwAAAA==.Salline:BAABLgAECn8jAAMeAAgJUgeNjAAiAQAeAAgJSQeNjAAiAQAVAAQJfAKdUwBdAAAAAA==.Samanda:BAABLgAECn8gAAIjAAcJkBONFQBqAQAjAAcJkBONFQBqAQAAAA==.Samshir:BAABLgAECn8ZAAIHAAgJyg2CdQB3AQAHAAgJyg2CdQB3AQAAAA==.',
Sc='Scorned:BAABLgAECn8zAAINAAgJBBNOTwCVAQANAAgJBBNOTwCVAQAAAA==.',
Se='Sekrain:BAAALgAECgQJBAAAAA==.Seosinz:BAABLgAECn8ZAAIMAAYJtBIPPAAdAQAMAAYJtBIPPAAdAQAAAA==.',
Sh='Shadowmane:BAAALgAECgEJAQAAAA==.Shamnasty:BAAALgAECgcJEwAAAA==.Shariaan:BAAALgAECgQJBAAAAA==.Shaylinn:BAAALgAECgMJBAAAAA==.Shenanigan:BAAALgADCgEJAQABLgAECgkJLgAQAKYdAA==.Shukkvoker:BAAALgADCgQJBQABLgAECgcJDgAOAAAAAA==.',
Si='Siella:BAABLgAECn8wAAIJAAgJ+hMgIAC/AQAJAAgJ+hMgIAC/AQAAAA==.Sileves:BAAALgAECgEJAgABLgAECgUJCwAOAAAAAA==.Sitrom:BAAALgAECgUJCwAAAA==.',
Sn='Snayd:BAABLgAECn8sAAMXAAgJfiFHHwCgAgAXAAgJfiFHHwCgAgAkAAEJWhVFEgBAAAAAAA==.Snowette:BAAALgADCgIJAgAAAA==.',
So='Solar:BAAALgAFFAIJAgAAAA==.Somenai:BAAALgAECgEJAgAAAA==.Sonofmums:BAAALgAECgkJBgAAAA==.Sora:BAAALgADCgIJAgABLgAECgEJAQAOAAAAAA==.Soulbaine:BAABLgAECn8aAAMCAAcJuBakGgCHAQACAAcJuBakGgCHAQAHAAQJRhJC7gDAAAAAAA==.',
Sp='Spazeric:BAABLgAECn8kAAMKAAkJzxT8HgAeAgAKAAkJzxT8HgAeAgAlAAcJKBZCMwA1AQAAAA==.Spheria:BAABLgAECn85AAIFAAkJ4wgFaQBrAQAFAAkJ4wgFaQBrAQAAAA==.',
St='Stalon:BAAALgADCgYJDgAAAA==.Strangeluve:BAAALgAECgcJEQAAAA==.',
Su='Suerte:BAAALgADCggJDQAAAA==.Suzieq:BAAALgADCgMJBgAAAA==.',
Sy='Sysnootles:BAAALgADCgYJBwAAAA==.',
['Sà']='Sàyori:BAAALgAECgUJBwAAAA==.',
Ta='Tabrett:BAAALgAECgIJAgAAAA==.Talashara:BAAALgADCgEJAQAAAA==.Talashea:BAAALgAECgEJBAAAAA==.Tankdezoe:BAAALgAECgMJBAABLgAECggJEwAOAAAAAA==.Tarall:BAAALgAECgEJAQAAAA==.Taveres:BAAALgADCgEJAQAAAA==.Tax:BAABLgAECn8lAAIUAAgJmQeMFQAcAQAUAAgJmQeMFQAcAQAAAA==.',
Te='Tenara:BAAALgADCgkJEgAAAA==.Tequ:BAAALgAECgMJBAAAAA==.',
Ti='Tim:BAABLgAFFH8FAAIYAAMJ0RYbSgDDAAAYAAMJ0RYbSgDDAAAAAA==.Timeshadow:BAABLgAECn8dAAIgAAYJhwP4PwDCAAAgAAYJhwP4PwDCAAAAAA==.Tinakoffee:BAAALgAECgIJAgAAAA==.Tine:BAABLgAECn8oAAIXAAkJixeHRAALAgAXAAkJixeHRAALAgAAAA==.',
To='Tope:BAAALgAECgYJCwAAAA==.Toray:BAABLgAECn8iAAIQAAgJbBPzaACcAQAQAAgJbBPzaACcAQAAAA==.',
Tr='Triplesix:BAABLgAECn8WAAMmAAkJRA9xNADpAAAmAAkJRA9xNADpAAANAAcJ8ATgsADDAAAAAA==.Trittia:BAABLgAECn8rAAMdAAcJFRR5MwB9AQAdAAcJFRR5MwB9AQAPAAEJhA+kVAAsAAAAAA==.',
Tu='Tukk:BAABLgAECn8VAAMPAAcJGxLbHgA5AQAPAAcJ4hHbHgA5AQAcAAEJwAq9fwAoAAAAAA==.Turtle:BAAALgAECgEJBQAAAA==.',
Tw='Twigatron:BAABLgAECn8VAAILAAgJCBXQLgDnAQALAAgJCBXQLgDnAQABLgAECgcJEQAOAAAAAA==.Twigdin:BAAALgADCgMJAwAAAA==.Twigdun:BAAALgAECgMJBgAAAA==.',
Ty='Tynk:BAAALgAECgUJCgAAAA==.',
Ur='Urza:BAAALgAECgYJCgAAAA==.',
Va='Vaewind:BAAALgADCgMJAwAAAA==.Valethus:BAABLgAECn81AAMeAAkJVR38FQChAgAeAAkJVR38FQChAgAEAAIJVAgefgBNAAAAAA==.Valmaru:BAAALgADCgkJCQAAAA==.',
Ve='Vesp:BAAALgAECgQJBAAAAA==.Vexxa:BAABLgAECn8YAAINAAkJPBhGSgClAQANAAkJPBhGSgClAQAAAA==.',
Vi='Viridania:BAAALgAECgUJDgAAAA==.',
Vy='Vynd:BAAALgADCgkJDgABLgAECgYJBgAOAAAAAA==.',
Wa='Walkz:BAAALgAECgYJEAABLgAECgkJEgAOAAAAAA==.Warrockhealz:BAAALgADCgYJBgAAAA==.',
Wi='Wickedlight:BAABLgAECn89AAISAAkJOyD0BQD1AgASAAkJOyD0BQD1AgAAAA==.Wickedlock:BAAALgAECgQJCQAAAA==.Wiggleston:BAABLgAECn8nAAMIAAkJuxAeIAABAgAIAAkJuxAeIAABAgAQAAMJYwP7RgFjAAAAAA==.Willscarlet:BAABLgAECn8WAAIeAAcJFAVcowD3AAAeAAcJFAVcowD3AAAAAA==.',
Wo='Wollybully:BAAALgADCgQJBAABLgAECgYJFQATAAMMAA==.',
Wy='Wylethia:BAAALgAECgQJBAAAAA==.',
Xa='Xandris:BAAALgAECgEJAgABLgAECggJGQAHAMoNAA==.',
Yf='Yffre:BAAALgAECgYJBgAAAA==.',
Yh='Yhana:BAAALgADCggJEwAAAA==.',
Yo='Yozsh:BAAALgAECgYJBgAAAA==.',
Za='Zanthiava:BAAALgAECgIJAgAAAA==.Zarathia:BAABLgAECn8ZAAImAAcJfArQMQD5AAAmAAcJfArQMQD5AAAAAA==.Zaritym:BAABLgAECn8cAAMKAAgJhRnMHAAuAgAKAAgJhRnMHAAuAgAlAAQJbw/gZgCGAAAAAA==.Zarrilin:BAABLgAECn8oAAIXAAkJlBd8RAAMAgAXAAkJlBd8RAAMAgAAAA==.',
Ze='Zebop:BAAALgAECgEJAgAAAA==.Zeeley:BAAALgADCgYJCgAAAA==.Zelsada:BAAALgAECgEJAQAAAA==.',
Zi='Zibetha:BAACLgAFFH8SAAIGAAUJ9RC3BgAqAQAGAAUJ9RC3BgAqAQAuAAQKf0kAAgYACQnSHvwBAKsCAAYACQnSHvwBAKsCAAAA.',
Zo='Zoeheals:BAAALgAECggJEwAAAA==.',
Zu='Zuggtmoy:BAAALgADCgkJCgAAAA==.Zulmahn:BAABLgAECn8jAAMYAAgJ1w7eTAB6AQAYAAgJ1w7eTAB6AQAWAAYJJASZbACgAAAAAA==.',
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
