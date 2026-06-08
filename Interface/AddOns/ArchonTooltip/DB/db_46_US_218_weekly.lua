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

local lookup = {'DeathKnight-Frost','DeathKnight-Blood','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Paladin-Holy','Priest-Holy','Monk-Mistweaver','Druid-Restoration','Druid-Balance','DemonHunter-Devourer','Unknown-Unknown','Warrior-Protection','Paladin-Retribution','Monk-Brewmaster','Priest-Shadow','Warlock-Affliction','Hunter-Survival','Shaman-Elemental','Mage-Frost','Shaman-Restoration','Priest-Discipline','Evoker-Augmentation','Evoker-Preservation','Warrior-Arms','Warrior-Fury','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Vengeance','Rogue-Outlaw','Druid-Feral','Mage-Fire','Monk-Windwalker','DemonHunter-Havoc',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=46,date='2026-06-07',data={Ab='Absolver:BAAALgADCgYJCwAAAA==.',
Ad='Adabisi:BAAALgADCgQJBQAAAA==.Addu:BAAALgAECgUJBQAAAA==.Adiforis:BAABLgAECn8VAAMBAAYJ6Q1NGAAFAQABAAYJ6Q1NGAAFAQACAAQJFgfLRQBrAAAAAA==.Adobo:BAAALgAFFAQJBAAAAA==.',
Ae='Aeralina:BAABLgAECn8XAAIDAAgJpQmoEwAYAQADAAgJpQmoEwAYAQAAAA==.Aerandir:BAABLgAECn8UAAMEAAYJNQrjrwD5AAAEAAYJNQrjrwD5AAAFAAEJAAAXeQAqAAABLgAECggJGQAGAMoNAA==.Aerwyn:BAAALgAECgYJBgAAAA==.',
Ah='Ahmyra:BAAALgAECgcJEwAAAA==.',
Al='Alessar:BAAALgAECgYJDAAAAA==.Allysson:BAABLgAECn8vAAIBAAkJ1BJjCQDfAQABAAkJ1BJjCQDfAQAAAA==.Alrekur:BAAALgAECgIJAgAAAA==.Alyestra:BAABLgAECn8UAAIHAAcJshL5MACLAQAHAAcJshL5MACLAQAAAA==.',
Am='Ambien:BAAALgAECgMJBQAAAA==.',
An='Anibundance:BAAALgAECgcJDAABLgAECgkJLQAIAJ0iAA==.Animyst:BAACLgAFFH8IAAIJAAQJ8hzNIABAAQAJAAQJ8hzNIABAAQAuAAQKfz8AAgkACQm6IxoDAIUDAAkACQm6IxoDAIUDAAEuAAQKCQktAAgAnSIA.Anipaltu:BAACLgAFFH8IAAIHAAQJsAxwJQDtAAAHAAQJsAxwJQDtAAAuAAQKfx4AAgcACQm2HUoIAP0CAAcACQm2HUoIAP0CAAEuAAQKCQktAAgAnSIA.Aniron:BAABLgAECn8UAAIEAAYJchG1iAAkAQAEAAYJchG1iAAkAQABLgAECgkJLQAIAJ0iAA==.Anirot:BAABLgAECn8tAAIIAAkJnSIvBAA7AwAIAAkJnSIvBAA7AwAAAA==.Anithwip:BAAALgAECgYJBgABLgAECgkJLQAIAJ0iAA==.Antoni:BAAALgAECgEJAQAAAA==.',
Ap='Aphirym:BAAALgAECgIJAgAAAA==.',
Ar='Aranta:BAABLgAECn8aAAMKAAYJmQ4PXwAQAQAKAAYJmQ4PXwAQAQALAAYJ9AlzTQDKAAAAAA==.Arcanium:BAAALgAECgEJAgAAAA==.',
As='Astren:BAAALgAECgEJAQAAAA==.Asynsia:BAABLgAECn8oAAIMAAkJZiHCDwC8AgAMAAkJZiHCDwC8AgAAAA==.',
Av='Avamani:BAAALgADCgkJCQAAAA==.',
Az='Azulmoon:BAAALgAECgYJCwAAAA==.',
Ba='Balrogg:BAAALgADCgcJBwAAAA==.Bartholomew:BAABLgAECn8lAAIJAAkJphz0CgDaAgAJAAkJphz0CgDaAgAAAA==.Bartno:BAAALgAECgIJAQAAAA==.',
Be='Beefed:BAAALgADCgIJAgAAAA==.Bessie:BAAALgADCgIJAgAAAA==.',
Bi='Bienfaiseur:BAABLgAECn84AAIIAAkJBSU7AQCvAwAIAAkJBSU7AQCvAwAAAA==.Bigtonka:BAAALgADCgYJBgAAAA==.',
Bl='Bladez:BAAALgAECgUJBgAAAA==.',
Bo='Boffadeez:BAAALgAECgQJBgAAAA==.Boombawks:BAAALgADCgUJBQABLgAECgEJAgANAAAAAA==.Boryndin:BAABLgAECn8iAAIOAAkJohkqDQAPAgAOAAkJohkqDQAPAgAAAA==.',
Br='Brad:BAAALgADCgIJAgAAAA==.Breadburn:BAAALgADCggJCAAAAA==.Breezybb:BAACLgAFFH8LAAIPAAQJaQ+bQwAYAQAPAAQJaQ+bQwAYAQAuAAQKfzcAAg8ACQm6Gyw6ADoCAA8ACQm6Gyw6ADoCAAAA.Brewfist:BAAALgADCgUJBQAAAA==.',
Bu='Bulgrim:BAAALgADCgYJCQAAAA==.',
Ca='Camhawk:BAAALgADCgkJCQAAAA==.Catastrophe:BAAALgAECgcJBwABLgAECgkJLAAQALEPAA==.',
Ce='Cearylin:BAAALgADCgcJEwAAAA==.Cering:BAAALgAECgYJBgAAAA==.',
Ch='Changsauce:BAAALgAECgYJDAAAAA==.Cherypoptart:BAABLgAECn8eAAIRAAgJKiBdDACFAgARAAgJKiBdDACFAgAAAA==.Chrismeister:BAAALgAECgYJEwAAAA==.',
Cl='Claymordon:BAAALgADCgYJBgAAAA==.Clothpally:BAAALgAECgkJDgAAAA==.',
Co='Codah:BAAALgAECgIJBgAAAA==.Coomonka:BAAALgADCgcJCQAAAA==.Coraggioso:BAAALgADCgYJBgAAAA==.Corbenik:BAAALgAECgIJBgABLgAECgcJGAAEAPEHAA==.',
Cr='Creel:BAAALgADCgYJBgAAAA==.Crethasmus:BAAALgAECgYJCAAAAA==.Crettephal:BAEBLgAECn8WAAISAAUJYxTmFAAWAQASAAUJYxTmFAAWAQAAAA==.Crodo:BAAALgADCgYJBgAAAA==.Cruella:BAAALgADCgEJAQAAAA==.',
['Cä']='Cähira:BAAALgADCgcJCwABLgADCgkJDwANAAAAAA==.',
Da='Daellan:BAAALgAECgUJCQAAAA==.Dainaira:BAAALgAECggJDwAAAA==.Daisia:BAABLgAECn8bAAITAAgJrQavKgBJAQATAAgJrQavKgBJAQAAAA==.Dalarrong:BAAALgAECgMJAwAAAA==.Dasteaire:BAAALgAECgMJBgAAAA==.',
De='Deathdealler:BAAALgAECgYJDAAAAA==.Deathstopper:BAAALgAECgEJAQAAAA==.Demonicadhd:BAAALgAECgYJEwAAAA==.Demonsmind:BAABLgAECn8ZAAMEAAgJphHNcwBNAQAEAAcJwBDNcwBNAQAFAAMJqhEuQQCwAAAAAA==.Derien:BAABLgAECn8mAAIOAAgJQRgdEQDMAQAOAAgJQRgdEQDMAQAAAA==.Derienfu:BAAALgAECgYJBgAAAA==.Devour:BAAALgAECgcJEgAAAA==.Dezin:BAAALgAECgYJBgAAAA==.',
Di='Dinkeldorf:BAAALgAECgMJBAABLgAFFAIJAgANAAAAAA==.',
Dk='Dkerien:BAAALgAECggJCAAAAA==.',
Do='Donkeyteeth:BAABLgAECn8fAAIUAAgJEQ+7NwBMAQAUAAgJEQ+7NwBMAQAAAA==.Downtownbuu:BAAALgADCgcJDAAAAA==.',
Dr='Dracarian:BAAALgADCgMJAwAAAA==.Dracorz:BAAALgAECgYJCwAAAA==.Draqula:BAAALgADCggJEgAAAA==.Dru:BAAALgADCgcJBwAAAA==.Drywater:BAABLgAECn8yAAIVAAgJXRBnbQCaAQAVAAgJXRBnbQCaAQAAAA==.',
Du='Dura:BAABLgAECn8wAAIWAAgJWBgGIgA2AgAWAAgJWBgGIgA2AgAAAA==.',
El='Eldunari:BAAALgAECgQJBAAAAA==.Elfblood:BAABLgAECn8+AAIFAAkJKwv5DgBCAQAFAAkJKwv5DgBCAQAAAA==.Elvion:BAAALgAECgMJBQAAAA==.',
Em='Emollama:BAABLgAECn9EAAMGAAkJyg0LUQDKAQAGAAkJyg0LUQDKAQACAAEJJwJpTQAcAAAAAA==.',
En='Engine:BAAALgADCgQJBAAAAA==.',
Er='Erazer:BAAALgADCgMJAwAAAA==.Erilana:BAAALgAECgEJBAABLgAECgUJCwANAAAAAA==.',
Et='Etiimasi:BAAALgADCgYJBwAAAA==.',
Ez='Ezanot:BAAALgADCgYJBgAAAA==.',
['Eï']='Eïr:BAAALgAECgQJCAABLgAFFAIJAgANAAAAAA==.',
Fa='Fabulosa:BAABLgAECn8tAAQRAAgJtAy7LgBeAQARAAgJtAy7LgBeAQAXAAYJ2wnjLwAhAQAIAAUJYAoVUwCCAAAAAA==.Faith:BAABLgAECn8fAAIPAAYJlxxrbgCHAQAPAAYJlxxrbgCHAQAAAA==.',
Fi='Finiquito:BAAALgADCgMJAwAAAA==.Finite:BAAALgAECgYJBgABLgAECgkJLgAPAKYdAA==.Firebug:BAABLgAECn8aAAIOAAcJDgdSKwDSAAAOAAcJDgdSKwDSAAAAAA==.',
Fn='Fndruid:BAAALgADCgEJAQAAAA==.Fnmage:BAAALgAECgQJCwAAAA==.',
Fr='Frieren:BAAALgAECgMJAwABLgAFFAUJHwAYAGcjAA==.',
Fu='Furnok:BAABLgAECn84AAMUAAkJCBQ3HAD0AQAUAAkJCBQ3HAD0AQAWAAcJMw2yYQApAQAAAA==.Fuzzyshukk:BAAALgAECgcJDgAAAA==.',
Ga='Galethia:BAAALgADCgkJJgAAAA==.Garli:BAAALgADCgMJAwAAAA==.',
Ge='Gerkin:BAAALgADCgcJDwAAAA==.',
Gg='Ggcthulhu:BAAALgAECgMJBQABLgAFFAQJBwAZAJ8IAA==.',
Gh='Ghutz:BAACLgAFFH8RAAIaAAMJpQ7CJADIAAAaAAMJpQ7CJADIAAAuAAQKfzoAAxoACQm6F98MABACABoACQm6F98MABACABsABwmICzZIAIMBAAAA.',
Gl='Glitterhoof:BAABLgAECn8gAAIHAAkJjxnyFgBIAgAHAAkJjxnyFgBIAgAAAA==.Glorblariirn:BAAALgADCgYJBgAAAA==.',
Go='Goliath:BAAALgAECgUJCwAAAA==.Gonja:BAAALgADCgYJEgAAAA==.',
Gr='Grimbjorne:BAAALgADCgcJBwAAAA==.Grimmbeardd:BAAALgADCgYJCgAAAA==.',
Gu='Gumbercules:BAABLgAECn8+AAIZAAkJYxP2CwASAgAZAAkJYxP2CwASAgAAAA==.',
Ha='Hammie:BAAALgADCgkJCQAAAA==.',
He='Hearthglen:BAABLgAECn8bAAIPAAgJsxH4dAB6AQAPAAgJsxH4dAB6AQAAAA==.',
Ho='Hollet:BAABLgAECn8hAAIcAAYJMRBHhQApAQAcAAYJMRBHhQApAQAAAA==.Holyblasto:BAAALgADCgEJAQAAAA==.Holyshukk:BAACLgAFFH8RAAIHAAUJpx4LDwC8AQAHAAUJpx4LDwC8AQAuAAQKfycAAwcACQmRIqEFABIDAAcACQmRIqEFABIDAA8AAQlCBw+fASgAAAEuAAQKBwkOAA0AAAAA.',
Hu='Huckk:BAAALgADCggJCwAAAA==.',
Hy='Hylen:BAAALgAECggJEgAAAA==.',
Ib='Ibrandul:BAABLgAECn81AAIPAAgJERQOYACnAQAPAAgJERQOYACnAQAAAA==.',
Ic='Icyveins:BAABLgAECn8UAAIVAAcJ8wHZAgGfAAAVAAcJ8wHZAgGfAAAAAA==.',
Ir='Iroha:BAAALgADCgQJBgAAAA==.Ironhuntress:BAABLgAECn8cAAIcAAgJ0xDvVQCXAQAcAAgJ0xDvVQCXAQAAAA==.',
It='Ithro:BAABLgAECn8nAAIdAAkJJxhPBQAdAgAdAAkJJxhPBQAdAgAAAA==.',
Iy='Iyachtu:BAAALgAECgkJEwAAAA==.',
Ja='Jarlo:BAABLgAECn8+AAIdAAkJoRo9AwB9AgAdAAkJoRo9AwB9AgAAAA==.',
Je='Jeffeory:BAAALgAECgIJAgABLgAECgkJLQAPAMUaAA==.Jefficiently:BAAALgAECgYJBgABLgAECgkJLQAPAMUaAA==.Jefriel:BAAALgAECgYJBgABLgAECgkJLQAPAMUaAA==.',
Jo='Jobu:BAAALgAECgEJAgAAAA==.Jormungandr:BAABLgAECn8oAAMaAAkJ1CHxBAC4AgAaAAkJ1CHxBAC4AgAOAAEJhAvYUAAuAAAAAA==.',
Ju='Juanhunglow:BAAALgAECgEJAQAAAA==.Judgederien:BAAALgAECgIJAgAAAA==.Jularity:BAAALgADCgYJBgAAAA==.',
Ka='Kaeldric:BAABLgAECn8uAAMGAAgJ7SEbGgCjAgAGAAgJ7SEbGgCjAgACAAEJ/w9qXAAoAAAAAA==.Kaladïn:BAAALgAECgEJAQAAAA==.Kalemshai:BAAALgADCgcJCwAAAA==.Kalinea:BAABLgAECn81AAIcAAcJUxRibQBcAQAcAAcJUxRibQBcAQAAAA==.Karyia:BAAALgAECgUJBQAAAA==.Kazuha:BAAALgAECgYJDgAAAA==.',
Ke='Kellerun:BAAALgADCgIJAgAAAA==.Keruptadin:BAAALgAECgUJBgAAAA==.Ketosis:BAAALgADCggJCgAAAA==.',
Ko='Kope:BAABLgAECn8rAAIZAAkJ/BrUBQCrAgAZAAkJ/BrUBQCrAgAAAA==.',
Kr='Kreltor:BAABLgAECn8oAAIWAAgJRiK0DADpAgAWAAgJRiK0DADpAgAAAA==.Kryptikz:BAAALgAECggJEQAAAA==.Krystoferson:BAABLgAECn8hAAIeAAgJUwL8NQDuAAAeAAgJUwL8NQDuAAAAAA==.',
La='Largar:BAAALgADCgUJCAAAAA==.',
Le='Leerroyy:BAAALgADCgIJAgAAAA==.Leesoftpaw:BAAALgADCgYJAgABLgAECgEJAgANAAAAAA==.Leianii:BAAALgAECgYJDAAAAA==.Lextali:BAAALgAECgQJBAAAAA==.',
Lh='Lhondar:BAAALgAECgQJBAAAAA==.',
Li='Liafail:BAABLgAECn8YAAIEAAcJ8QesgwBTAQAEAAcJ8QesgwBTAQAAAA==.Lillat:BAABLgAECn8XAAIIAAcJTg5uMABAAQAIAAcJTg5uMABAAQAAAA==.Lin:BAAALgAECgEJAQAAAA==.Liryv:BAAALgADCgYJFAAAAA==.Littlepop:BAAALgADCgEJAQAAAA==.',
Lo='Lollilock:BAAALgAECgcJBAAAAA==.',
Lu='Luena:BAAALgAECgYJEgAAAA==.Lugglugg:BAAALgAECgEJAQAAAA==.Lumbre:BAAALgADCgcJCQAAAA==.Luminara:BAAALgAECgQJBAAAAA==.Luuggork:BAAALgAECgEJAQAAAA==.',
Ly='Lyarith:BAAALgADCgUJBQAAAA==.Lyrà:BAAALgAECgQJAwAAAA==.',
['Lá']='Ládydèath:BAAALgAECgYJBAAAAA==.',
['Lì']='Lìesson:BAABLgAECn8tAAIPAAkJiCFCDwDjAgAPAAkJiCFCDwDjAgAAAA==.',
Ma='Mabo:BAAALgAECgEJAQAAAA==.Mackaroni:BAACLgAFFH8HAAIVAAQJWhBeYAAhAQAVAAQJWhBeYAAhAQAuAAQKfxoAAhUACAlSFiVfAL0BABUACAlSFiVfAL0BAAEuAAUUAgkCAA0AAAAA.Madolynne:BAAALgADCgIJAgAAAA==.Madrel:BAAALgADCgUJBQAAAA==.Magesca:BAABLgAECn9CAAIVAAkJLxlkLQBeAgAVAAkJLxlkLQBeAgAAAA==.Magimiester:BAAALgADCgEJAQABLgAECgYJEwANAAAAAA==.Mahalath:BAAALgADCgMJAwAAAA==.Makkagg:BAACLgAFFH8TAAMOAAQJDBrNDwAjAQAOAAQJvRnNDwAjAQAbAAIJkBKAPQCVAAAuAAQKfzUAAw4ACQkiIcUEAMsCAA4ACQkiIcUEAMsCABsACAlWDMc5AL8BAAAA.Malamur:BAAALgADCggJEgAAAA==.Malisea:BAABLgAECn8kAAIVAAkJswjhcgCPAQAVAAkJswjhcgCPAQAAAA==.',
Me='Melarndra:BAAALgADCgYJBgAAAA==.',
Mi='Milagrosa:BAABLgAECn8jAAIYAAkJJQ3nLAB/AQAYAAkJJQ3nLAB/AQAAAA==.Mirael:BAACLgAFFH8PAAIcAAUJqxy0MgA7AQAcAAUJqxy0MgA7AQAuAAQKfzAAAhwACQnKIMAIAAcDABwACQnKIMAIAAcDAAAA.Mishuntsalot:BAAALgADCgkJDwAAAA==.',
Mo='Molocherx:BAAALgADCgMJAwAAAA==.Mommacoo:BAABLgAECn8cAAIPAAYJRQkg1gDfAAAPAAYJRQkg1gDfAAAAAA==.Mori:BAAALgAECgEJAQAAAA==.',
Mu='Mumsms:BAAALgAECgkJBgAAAA==.Mumsurprise:BAAALgAECgkJAgAAAA==.',
My='Myrmia:BAABLgAECn8aAAIKAAcJvg2bVQAxAQAKAAcJvg2bVQAxAQAAAA==.Mystfang:BAABLgAECn8XAAIVAAkJNhOtSwDzAQAVAAkJNhOtSwDzAQAAAA==.',
['Mà']='Màck:BAAALgAFFAIJAgAAAA==.',
Na='Nade:BAAALgAECgcJBAAAAA==.Naldor:BAAALgADCgkJCQAAAA==.Nargul:BAABLgAECn8vAAIEAAcJbRuRPgDbAQAEAAcJbRuRPgDbAQAAAA==.Naturboom:BAAALgAECgEJAQAAAA==.',
Ne='Nekossian:BAAALgAECgYJCwABLgAECgkJLQAPAMUaAA==.',
Ni='Nickorvis:BAAALgADCgUJBQABLgAECgcJGAAEAPEHAA==.Nirazen:BAAALgAECgIJAgAAAA==.',
No='Nonae:BAEALgADCgYJBgAAAA==.Nota:BAABLgAECn8YAAIPAAcJigcjzwDpAAAPAAcJigcjzwDpAAAAAA==.',
Oa='Oathmere:BAAALgADCggJCwAAAA==.',
Og='Ogrusao:BAABLgAECn8gAAIcAAgJeA33WQCMAQAcAAgJeA33WQCMAQAAAA==.Ogun:BAAALgADCgIJAwAAAA==.',
Pa='Panasaurus:BAABLgAECn8+AAIfAAkJWRVqCADiAQAfAAkJWRVqCADiAQAAAA==.',
Pe='Pechuuga:BAABLgAECn8WAAIQAAcJwBmCMgCHAQAQAAcJwBmCMgCHAQAAAA==.Pelli:BAABLgAECn8uAAIRAAgJYAhYNwAwAQARAAgJYAhYNwAwAQAAAA==.Pendraig:BAAALgAECgYJCwAAAA==.Pestilense:BAAALgADCgIJAgAAAA==.',
Pl='Plaza:BAAALgAECgkJEgAAAA==.',
Qu='Quadrilio:BAAALgADCgUJBQAAAA==.Quamutei:BAAALgADCgUJBgAAAA==.',
Ra='Raylisarri:BAAALgAECgEJAgABLgAECgUJDgANAAAAAA==.Rayst:BAABLgAECn8dAAIVAAYJVQJoAgGgAAAVAAYJVQJoAgGgAAAAAA==.Razìel:BAAALgADCgMJAgAAAA==.',
Rh='Rhalek:BAACLgAFFH8GAAIKAAMJhxKvPAC3AAAKAAMJhxKvPAC3AAAuAAQKfx4AAgoACAkJISgMAPcCAAoACAkJISgMAPcCAAAA.Rheunae:BAAALgAECgQJBAAAAA==.Rhykis:BAABLgAECn8cAAIbAAgJIiGIEABuAgAbAAgJIiGIEABuAgAAAA==.',
Ri='Rilis:BAAALgADCgEJAQAAAA==.Rillyn:BAABLgAECn8xAAMTAAkJpxX7DwAtAgATAAkJQxX7DwAtAgAcAAEJ+hTUEQE9AAAAAA==.',
Ro='Rojei:BAAALgADCgYJBgAAAA==.Role:BAAALgADCgEJAQABLgAECggJLgAgAGUZAA==.',
Ru='Rubbin:BAAALgAECgEJAQAAAA==.',
Sa='Sabba:BAAALgADCgYJBgAAAA==.Sagearian:BAAALgAECgQJBQAAAA==.Salindill:BAAALgADCgMJAwAAAA==.Salline:BAABLgAECn8ZAAMcAAYJawjYqwDdAAAcAAYJXgjYqwDdAAATAAQJfALyUABfAAAAAA==.Samanda:BAABLgAECn8gAAIhAAcJkBMyFABvAQAhAAcJkBMyFABvAQAAAA==.Samshir:BAABLgAECn8ZAAIGAAgJyg0MbwB/AQAGAAgJyg0MbwB/AQAAAA==.',
Sc='Scorned:BAABLgAECn8yAAIMAAgJBBOJTACVAQAMAAgJBBOJTACVAQAAAA==.',
Se='Sekrain:BAAALgAECgQJBAAAAA==.Seosinz:BAABLgAECn8ZAAILAAYJtBILOgAeAQALAAYJtBILOgAeAQAAAA==.',
Sh='Shadowmane:BAAALgAECgEJAQAAAA==.Shamnasty:BAAALgAECgcJEwAAAA==.Shariaan:BAAALgAECgQJBAAAAA==.Shaylinn:BAAALgAECgEJAQAAAA==.Shenanigan:BAAALgADCgEJAQABLgAECgkJLgAPAKYdAA==.Shukkvoker:BAAALgADCgQJBQABLgAECgcJDgANAAAAAA==.',
Si='Siella:BAABLgAECn8wAAIIAAgJ+hOXHgDCAQAIAAgJ+hOXHgDCAQAAAA==.Sileves:BAAALgAECgEJAgABLgAECgUJCwANAAAAAA==.Sitrom:BAAALgAECgUJCwAAAA==.',
Sn='Snayd:BAABLgAECn8sAAMVAAgJfiGhHQCkAgAVAAgJfiGhHQCkAgAiAAEJWhULEQBAAAAAAA==.Snowette:BAAALgADCgIJAgAAAA==.',
So='Solar:BAAALgAFFAIJAgAAAA==.Somenai:BAAALgAECgEJAgAAAA==.Sonofmums:BAAALgAECgkJBgAAAA==.Sora:BAAALgADCgIJAgABLgAECgEJAQANAAAAAA==.Soulbaine:BAABLgAECn8aAAMCAAcJuBZ2GQCKAQACAAcJuBZ2GQCKAQAGAAQJRhID5QDEAAAAAA==.',
Sp='Spazeric:BAABLgAECn8fAAMJAAkJ3haBJADrAQAJAAgJcxWBJADrAQAjAAcJKBYuMQA2AQAAAA==.Spheria:BAABLgAECn80AAIEAAgJJQiKfwA1AQAEAAgJJQiKfwA1AQAAAA==.',
St='Stalon:BAAALgADCgYJDgAAAA==.Strangeluve:BAAALgAECgcJEQAAAA==.',
Su='Suerte:BAAALgADCggJDQAAAA==.Suzieq:BAAALgADCgMJAwAAAA==.',
Sy='Sysnootles:BAAALgADCgYJBwAAAA==.',
['Sà']='Sàyori:BAAALgAECgUJBwAAAA==.',
Ta='Tabrett:BAAALgAECgIJAgAAAA==.Talashara:BAAALgADCgEJAQAAAA==.Talashea:BAAALgAECgEJAgAAAA==.Tankdezoe:BAAALgAECgMJBAABLgAECggJEwANAAAAAA==.Tarall:BAAALgAECgEJAQAAAA==.Taveres:BAAALgADCgEJAQAAAA==.Tax:BAABLgAECn8bAAISAAYJpQbZGwDRAAASAAYJpQbZGwDRAAAAAA==.',
Te='Tenara:BAAALgADCgkJEgAAAA==.Tequ:BAAALgAECgEJAQAAAA==.',
Ti='Tim:BAABLgAFFH8FAAIWAAMJ0RYyRQDFAAAWAAMJ0RYyRQDFAAAAAA==.Timeshadow:BAABLgAECn8dAAIeAAYJhwOBPQDCAAAeAAYJhwOBPQDCAAAAAA==.Tinakoffee:BAAALgAECgIJAgAAAA==.Tine:BAABLgAECn8oAAIVAAkJixfoQAAUAgAVAAkJixfoQAAUAgAAAA==.',
To='Tope:BAAALgAECgYJCwAAAA==.Toray:BAABLgAECn8iAAIPAAgJbBN/ZACdAQAPAAgJbBN/ZACdAQAAAA==.',
Tr='Triplesix:BAABLgAECn8WAAMkAAkJRA/+MQDqAAAkAAkJRA/+MQDqAAAMAAcJ8AQbqwDDAAAAAA==.Trittia:BAABLgAECn8mAAMbAAcJJhAvOQBbAQAbAAcJTA8vOQBbAQAOAAEJhA+xUQAtAAAAAA==.',
Tu='Tukk:BAABLgAECn8UAAIOAAcJ4hF/HQA9AQAOAAcJ4hF/HQA9AQAAAA==.Turtle:BAAALgAECgEJBQAAAA==.',
Tw='Twigatron:BAABLgAECn8VAAIKAAgJCBXFLQDnAQAKAAgJCBXFLQDnAQABLgAECgcJEQANAAAAAA==.Twigdin:BAAALgADCgMJAwAAAA==.Twigdun:BAAALgAECgMJBgAAAA==.',
Ty='Tynk:BAAALgAECgIJAgABLgAECgQJBAANAAAAAA==.',
Ur='Urza:BAAALgAECgYJCgAAAA==.',
Va='Vaewind:BAAALgADCgMJAwAAAA==.Valethus:BAABLgAECn81AAMcAAkJVR08FACnAgAcAAkJVR08FACnAgADAAIJVAgefgBNAAAAAA==.Valmaru:BAAALgADCgkJCQAAAA==.',
Ve='Vesp:BAAALgAECgQJBAAAAA==.Vexxa:BAABLgAECn8YAAIMAAkJPBjJRwCkAQAMAAkJPBjJRwCkAQAAAA==.',
Vi='Viridania:BAAALgAECgUJBwAAAA==.',
Vy='Vynd:BAAALgADCgkJDgABLgAECgYJBgANAAAAAA==.',
Wa='Walkz:BAAALgAECgYJEAABLgAECggJEQANAAAAAA==.Warrockhealz:BAAALgADCgYJBgAAAA==.',
Wi='Wickedlight:BAABLgAECn84AAIRAAkJ4h4vBwDYAgARAAkJ4h4vBwDYAgAAAA==.Wiggleston:BAABLgAECn8gAAMHAAkJsBAcHwAAAgAHAAkJsBAcHwAAAgAPAAMJYwMPPAFjAAAAAA==.Willscarlet:BAABLgAECn8WAAIcAAcJFAUvnAD8AAAcAAcJFAUvnAD8AAAAAA==.',
Wy='Wylethia:BAAALgADCgcJCAAAAA==.',
Xa='Xandris:BAAALgAECgEJAgABLgAECggJGQAGAMoNAA==.',
Yf='Yffre:BAAALgAECgYJBgAAAA==.',
Yh='Yhana:BAAALgADCggJEwAAAA==.',
Yo='Yozsh:BAAALgAECgYJBgAAAA==.',
Za='Zarathia:BAABLgAECn8ZAAIkAAcJfAoCLwD8AAAkAAcJfAoCLwD8AAAAAA==.Zaritym:BAABLgAECn8cAAMJAAgJhRkxGwAtAgAJAAgJhRkxGwAtAgAjAAQJbw/RYgCGAAAAAA==.Zarrilin:BAABLgAECn8oAAIVAAkJlBdJQAAWAgAVAAkJlBdJQAAWAgAAAA==.',
Ze='Zebop:BAAALgAECgEJAgAAAA==.Zeeley:BAAALgADCgYJCgAAAA==.Zelsada:BAAALgAECgEJAQAAAA==.',
Zi='Zibetha:BAACLgAFFH8RAAIFAAUJ9RDpBQAvAQAFAAUJ9RDpBQAvAQAuAAQKf0gAAgUACQnSHtkBAK0CAAUACQnSHtkBAK0CAAAA.',
Zo='Zoeheals:BAAALgAECggJEwAAAA==.',
Zu='Zuggtmoy:BAAALgADCgkJCgAAAA==.Zulmahn:BAABLgAECn8jAAMWAAgJ1w4LSgB7AQAWAAgJ1w4LSgB7AQAUAAYJJARaaACgAAAAAA==.',
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
